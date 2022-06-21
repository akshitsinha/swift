#!/usr/bin/env python3
#
# ==-- process-stats-dir - summarize one or more Swift -stats-output-dirs --==#
#
# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
#
# ==------------------------------------------------------------------------==#
#
# This file processes the contents of one or more directories generated by
# `swiftc -stats-output-dir` and emits summary data, traces etc. for analysis.

import argparse
import csv
import io
import itertools
import json
import os
import platform
import re
import sys
import time
import urllib
from collections import namedtuple
from operator import attrgetter

from jobstats import (list_stats_dir_profiles,
                      load_stats_dir, merge_all_jobstats)

if sys.version_info[0] < 3:
    import urllib2
    Request = urllib2.Request
    URLOpen = urllib2.urlopen
else:
    import urllib.request
    import urllib.parse
    import urllib.error
    Request = urllib.request.Request
    URLOpen = urllib.request.urlopen

MODULE_PAT = re.compile(r'^(\w+)\.')


def module_name_of_stat(name):
    return re.match(MODULE_PAT, name).groups()[0]


def stat_name_minus_module(name):
    return re.sub(MODULE_PAT, '', name)


# Perform any custom processing of args here, in particular the
# select_stats_from_csv_baseline step, which is a bit subtle.
def vars_of_args(args):
    vargs = vars(args)
    if args.select_stats_from_csv_baseline is not None:
        with io.open(args.select_stats_from_csv_baseline, 'r', encoding='utf-8') as f:
            b = read_stats_dict_from_csv(f)
        # Sniff baseline stat-names to figure out if they're module-qualified
        # even when the user isn't asking us to _output_ module-grouped data.
        all_triples = all(len(k.split('.')) == 3 for k in b.keys())
        if args.group_by_module or all_triples:
            vargs['select_stat'] = set(stat_name_minus_module(k)
                                       for k in b.keys())
        else:
            vargs['select_stat'] = b.keys()
    return vargs


# Passed args with 2-element remainder ["old", "new"], return a list of tuples
# of the form [(name, (oldstats, newstats))] where each name is a common subdir
# of each of "old" and "new", and the stats are those found in the respective
# dirs.
def load_paired_stats_dirs(args):
    assert(len(args.remainder) == 2)
    paired_stats = []
    (old, new) = args.remainder
    vargs = vars_of_args(args)
    for p in sorted(os.listdir(old)):
        full_old = os.path.join(old, p)
        full_new = os.path.join(new, p)
        if not (os.path.exists(full_old) and os.path.isdir(full_old) and
                os.path.exists(full_new) and os.path.isdir(full_new)):
            continue
        old_stats = load_stats_dir(full_old, **vargs)
        new_stats = load_stats_dir(full_new, **vargs)
        if len(old_stats) == 0 or len(new_stats) == 0:
            continue
        paired_stats.append((p, (old_stats, new_stats)))
    return paired_stats


def write_catapult_trace(args):
    allstats = []
    vargs = vars_of_args(args)
    for path in args.remainder:
        allstats += load_stats_dir(path, **vargs)
    allstats.sort(key=attrgetter('start_usec'))
    for i in range(len(allstats)):
        allstats[i].jobid = i
    json.dump([s.to_catapult_trace_obj() for s in allstats], args.output)


def write_lnt_values(args):
    vargs = vars_of_args(args)
    for d in args.remainder:
        stats = load_stats_dir(d, **vargs)
        merged = merge_all_jobstats(stats, **vargs)
        j = merged.to_lnt_test_obj(args)
        if args.lnt_submit is None:
            json.dump(j, args.output, indent=4)
        else:
            url = args.lnt_submit
            print("\nsubmitting to LNT server: " + url)
            json_report = {'input_data': json.dumps(j), 'commit': '1'}
            data = urllib.urlencode(json_report)
            response_str = URLOpen(Request(url, data))
            response = json.loads(response_str.read())
            print("### response:")
            print(response)
            if 'success' in response:
                print("server response:\tSuccess")
            else:
                print("server response:\tError")
                print("error:\t", response['error'])
                sys.exit(1)


def show_paired_incrementality(args):
    fieldnames = ["old_pct", "old_skip",
                  "new_pct", "new_skip",
                  "delta_pct", "delta_skip",
                  "name"]
    out = csv.DictWriter(args.output, fieldnames, dialect='excel-tab')
    out.writeheader()
    vargs = vars_of_args(args)

    for (name, (oldstats, newstats)) in load_paired_stats_dirs(args):
        olddriver = merge_all_jobstats((x for x in oldstats
                                        if x.is_driver_job()), **vargs)
        newdriver = merge_all_jobstats((x for x in newstats
                                        if x.is_driver_job()), **vargs)
        if olddriver is None or newdriver is None:
            continue
        oldpct = olddriver.incrementality_percentage()
        newpct = newdriver.incrementality_percentage()
        deltapct = newpct - oldpct
        oldskip = olddriver.driver_jobs_skipped()
        newskip = newdriver.driver_jobs_skipped()
        deltaskip = newskip - oldskip
        out.writerow(dict(name=name,
                          old_pct=oldpct, old_skip=oldskip,
                          new_pct=newpct, new_skip=newskip,
                          delta_pct=deltapct, delta_skip=deltaskip))


def show_incrementality(args):
    fieldnames = ["incrementality", "name"]
    out = csv.DictWriter(args.output, fieldnames, dialect='excel-tab')
    out.writeheader()

    vargs = vars_of_args(args)
    for path in args.remainder:
        stats = load_stats_dir(path, **vargs)
        for s in stats:
            if s.is_driver_job():
                pct = s.incrementality_percentage()
                out.writerow(dict(name=os.path.basename(path),
                                  incrementality=pct))


def diff_and_pct(old, new):
    if old == 0:
        if new == 0:
            return (0, 0.0)
        else:
            return (new, 100.0)
    delta = (new - old)
    delta_pct = round((float(delta) / float(old)) * 100.0, 2)
    return (delta, delta_pct)


def update_epoch_value(d, name, epoch, value):
    changed = 0
    if name in d:
        (existing_epoch, existing_value) = d[name]
        if existing_epoch > epoch:
            print("note: keeping newer value %d from epoch %d for %s"
                  % (existing_value, existing_epoch, name))
            epoch = existing_epoch
            value = existing_value
        elif existing_value == value:
            epoch = existing_epoch
        else:
            (_, delta_pct) = diff_and_pct(existing_value, value)
            print("note: changing value %d -> %d (%.2f%%) for %s" %
                  (existing_value, value, delta_pct, name))
            changed = 1
    d[name] = (epoch, value)
    return (epoch, value, changed)


def read_stats_dict_from_csv(f, select_stat=''):
    infieldnames = ["epoch", "name", "value"]
    c = csv.DictReader(f, infieldnames,
                       dialect='excel-tab',
                       quoting=csv.QUOTE_NONNUMERIC)
    d = {}
    sre = re.compile('.*' if len(select_stat) == 0 else
                     '|'.join(select_stat))
    for row in c:
        epoch = int(row["epoch"])
        name = row["name"]
        if sre.search(name) is None:
            continue
        value = int(row["value"])
        update_epoch_value(d, name, epoch, value)
    return d


# The idea here is that a "baseline" is a (tab-separated) CSV file full of
# the counters you want to track, each prefixed by an epoch timestamp of
# the last time the value was reset.
#
# When you set a fresh baseline, all stats in the provided stats dir are
# written to the baseline. When you set against an _existing_ baseline,
# only the counters mentioned in the existing baseline are updated, and
# only if their values differ.
#
# Finally, since it's a line-oriented CSV file, you can put:
#
#    mybaseline.csv merge=union
#
# in your .gitattributes file, and forget about merge conflicts. The reader
# function above will take the later epoch anytime it detects duplicates,
# so union-merging is harmless. Duplicates will be eliminated whenever the
# next baseline-set is done.
def set_csv_baseline(args):
    existing = None
    vargs = vars_of_args(args)
    if os.path.exists(args.set_csv_baseline):
        with io.open(args.set_csv_baseline, "r", encoding='utf-8', newline='\n') as f:
            ss = vargs['select_stat']
            existing = read_stats_dict_from_csv(f, select_stat=ss)
            print("updating %d baseline entries in %s" %
                  (len(existing), args.set_csv_baseline))
    else:
        print("making new baseline " + args.set_csv_baseline)
    fieldnames = ["epoch", "name", "value"]

    def _open(path):
        if sys.version_info[0] < 3:
            return open(path, 'wb')
        return io.open(path, "w", encoding='utf-8', newline='\n')

    with _open(args.set_csv_baseline) as f:
        out = csv.DictWriter(f, fieldnames, dialect='excel-tab',
                             quoting=csv.QUOTE_NONNUMERIC)
        m = merge_all_jobstats((s for d in args.remainder
                                for s in load_stats_dir(d, **vargs)),
                               **vargs)
        if m is None:
            print("no stats found")
            return 1
        changed = 0
        newepoch = int(time.time())
        for name in sorted(m.stats.keys()):
            epoch = newepoch
            value = m.stats[name]
            if existing is not None:
                if name not in existing:
                    continue
                (epoch, value, chg) = update_epoch_value(existing, name,
                                                         epoch, value)
                changed += chg
            out.writerow(dict(epoch=int(epoch),
                              name=name,
                              value=int(value)))
        if existing is not None:
            print("changed %d entries in baseline" % changed)
    return 0


OutputRow = namedtuple("OutputRow",
                       ["name", "old", "new",
                        "delta", "delta_pct"])


def compare_stats(args, old_stats, new_stats):
    for name in sorted(old_stats.keys()):
        old = old_stats[name]
        new = new_stats.get(name, 0)
        (delta, delta_pct) = diff_and_pct(old, new)
        yield OutputRow(name=name,
                        old=int(old), new=int(new),
                        delta=int(delta),
                        delta_pct=delta_pct)


IMPROVED = -1
UNCHANGED = 0
REGRESSED = 1


def row_state(row, args):
    delta_pct_over_thresh = abs(row.delta_pct) > args.delta_pct_thresh
    if (row.name.startswith("time.") or '.time.' in row.name):
        # Timers are judged as changing if they exceed
        # the percentage _and_ absolute-time thresholds
        delta_usec_over_thresh = abs(row.delta) > args.delta_usec_thresh
        if delta_pct_over_thresh and delta_usec_over_thresh:
            return (REGRESSED if row.delta > 0 else IMPROVED)
    elif delta_pct_over_thresh:
        return (REGRESSED if row.delta > 0 else IMPROVED)
    return UNCHANGED


def write_comparison(args, old_stats, new_stats):
    rows = list(compare_stats(args, old_stats, new_stats))
    sort_key = (attrgetter('delta_pct')
                if args.sort_by_delta_pct
                else attrgetter('name'))

    regressed = [r for r in rows if row_state(r, args) == REGRESSED]
    unchanged = [r for r in rows if row_state(r, args) == UNCHANGED]
    improved = [r for r in rows if row_state(r, args) == IMPROVED]
    regressions = len(regressed)

    if args.markdown:

        def format_time(v):
            if abs(v) > 1000000:
                return "{:.1f}s".format(v / 1000000.0)
            elif abs(v) > 1000:
                return "{:.1f}ms".format(v / 1000.0)
            else:
                return "{:.1f}us".format(v)

        def format_field(field, row):
            if field == 'name':
                if args.group_by_module:
                    return stat_name_minus_module(row.name)
                else:
                    return row.name
            elif field == 'delta_pct':
                s = str(row.delta_pct) + "%"
                if args.github_emoji:
                    if row_state(row, args) == REGRESSED:
                        s += " :no_entry:"
                    elif row_state(row, args) == IMPROVED:
                        s += " :white_check_mark:"
                return s
            else:
                v = int(vars(row)[field])
                if row.name.startswith('time.'):
                    return format_time(v)
                else:
                    return "{:,d}".format(v)

        def format_table(elts):
            out = args.output
            out.write('\n')
            out.write(' | '.join(OutputRow._fields))
            out.write('\n')
            out.write(' | '.join('---:' for _ in OutputRow._fields))
            out.write('\n')
            for e in elts:
                out.write(' | '.join(format_field(f, e)
                                     for f in OutputRow._fields))
                out.write('\n')

        def format_details(name, elts, is_closed):
            out = args.output
            details = '<details>\n' if is_closed else '<details open>\n'
            out.write(details)
            out.write('<summary>%s (%d)</summary>\n'
                      % (name, len(elts)))
            if args.group_by_module:
                def keyfunc(e):
                    return module_name_of_stat(e.name)
                elts.sort(key=attrgetter('name'))
                for mod, group in itertools.groupby(elts, keyfunc):
                    groupelts = list(group)
                    groupelts.sort(key=sort_key, reverse=args.sort_descending)
                    out.write(details)
                    out.write('<summary>%s in %s (%d)</summary>\n'
                              % (name, mod, len(groupelts)))
                    format_table(groupelts)
                    out.write('</details>\n')
            else:
                elts.sort(key=sort_key, reverse=args.sort_descending)
                format_table(elts)
            out.write('</details>\n')

        closed_regressions = (args.close_regressions or len(regressed) == 0)
        format_details('Regressed', regressed, closed_regressions)
        format_details('Improved', improved, True)
        format_details('Unchanged (delta < %s%% or delta < %s)' %
                       (args.delta_pct_thresh,
                        format_time(args.delta_usec_thresh)),
                       unchanged, True)

    else:
        rows.sort(key=sort_key, reverse=args.sort_descending)
        out = csv.DictWriter(args.output, OutputRow._fields,
                             dialect='excel-tab')
        out.writeheader()
        for row in rows:
            if row_state(row, args) != UNCHANGED:
                out.writerow(row._asdict())

    return regressions


def compare_to_csv_baseline(args):
    vargs = vars_of_args(args)
    with io.open(args.compare_to_csv_baseline, 'r', encoding='utf-8') as f:
        old_stats = read_stats_dict_from_csv(f, select_stat=vargs['select_stat'])
    m = merge_all_jobstats((s for d in args.remainder
                            for s in load_stats_dir(d, **vargs)),
                           **vargs)
    old_stats = dict((k, v) for (k, (_, v)) in old_stats.items())
    new_stats = m.stats

    return write_comparison(args, old_stats, new_stats)


# Summarize immediate difference between two stats-dirs, optionally
def compare_stats_dirs(args):
    if len(args.remainder) != 2:
        raise ValueError("Expected exactly 2 stats-dirs")

    vargs = vars_of_args(args)
    (old, new) = args.remainder
    old_stats = merge_all_jobstats(load_stats_dir(old, **vargs), **vargs)
    new_stats = merge_all_jobstats(load_stats_dir(new, **vargs), **vargs)

    return write_comparison(args, old_stats.stats, new_stats.stats)


# Evaluate a boolean expression in terms of the provided stats-dir; all stats
# are projected into python dicts (thus variables in the eval expr) named by
# the last identifier in the stat definition. This means you can evaluate
# things like 'NumIRInsts < 1000' or
# 'NumTypesValidated == NumTypesDeserialized'
def evaluate(args):
    if len(args.remainder) != 1:
        raise ValueError("Expected exactly 1 stats-dir to evaluate against")

    d = args.remainder[0]
    vargs = vars_of_args(args)
    merged = merge_all_jobstats(load_stats_dir(d, **vargs), **vargs)
    env = {}
    ident = re.compile(r'(\w+)$')
    for (k, v) in merged.stats.items():
        if k.startswith("time.") or '.time.' in k:
            continue
        m = re.search(ident, k)
        if m:
            i = m.groups()[0]
            if args.verbose:
                print("%s => %s" % (i, v))
            env[i] = v
    try:
        if eval(args.evaluate, env):
            return 0
        else:
            print("evaluate condition failed: '%s'" % args.evaluate)
            return 1
    except Exception as e:
        print(e)
        return 1


# Evaluate a boolean expression in terms of deltas between the provided two
# stats-dirs; works like evaluate() above but on absolute differences
def evaluate_delta(args):
    if len(args.remainder) != 2:
        raise ValueError("Expected exactly 2 stats-dirs to evaluate-delta")

    (old, new) = args.remainder
    vargs = vars_of_args(args)
    old_stats = merge_all_jobstats(load_stats_dir(old, **vargs), **vargs)
    new_stats = merge_all_jobstats(load_stats_dir(new, **vargs), **vargs)

    env = {}
    ident = re.compile(r'(\w+)$')
    for r in compare_stats(args, old_stats.stats, new_stats.stats):
        if r.name.startswith("time.") or '.time.' in r.name:
            continue
        m = re.search(ident, r.name)
        if m:
            i = m.groups()[0]
            if args.verbose:
                print("%s => %s" % (i, r.delta))
            env[i] = r.delta
    try:
        if eval(args.evaluate_delta, env):
            return 0
        else:
            print("evaluate-delta condition failed: '%s'" %
                  args.evaluate_delta)
            return 1
    except Exception as e:
        print(e)
        return 1


def render_profiles(args):
    flamegraph_pl = args.flamegraph_script
    if flamegraph_pl is None:
        import distutils.spawn
        flamegraph_pl = distutils.spawn.find_executable("flamegraph.pl")
    if flamegraph_pl is None:
        print("Need flamegraph.pl in $PATH, or pass --flamegraph-script")

    vargs = vars_of_args(args)
    for statsdir in args.remainder:
        jobprofs = list_stats_dir_profiles(statsdir, **vargs)
        index_path = os.path.join(statsdir, "profile-index.html")
        all_profile_types = set([k for keys in [j.profiles.keys()
                                                for j in jobprofs
                                                if j.profiles is not None]
                                 for k in keys])
        with open(index_path, "wb") as index:
            for ptype in all_profile_types:
                index.write("<h2>Profile type: " + ptype + "</h2>\n")
                index.write("<ul>\n")
                for j in jobprofs:
                    if j.is_frontend_job():
                        index.write("    <li>" +
                                    ("Module %s :: %s" %
                                     (j.module, " ".join(j.jobargs))) + "\n")
                        index.write("    <ul>\n")
                        profiles = sorted(j.profiles.get(ptype, {}).items())
                        for counter, path in profiles:
                            title = ("Module: %s, File: %s, "
                                     "Counter: %s, Profile: %s" %
                                     (j.module, j.input, counter, ptype))
                            subtitle = j.triple + ", -" + j.opt
                            svg = os.path.abspath(path + ".svg")
                            with open(path) as p, open(svg, "wb") as g:
                                import subprocess
                                print("Building flamegraph " + svg)
                                subprocess.check_call([flamegraph_pl,
                                                       "--title", title,
                                                       "--subtitle", subtitle],
                                                      stdin=p, stdout=g)
                            link = ("<tt><a href=\"file://%s\">%s</a></tt>" %
                                    (svg, counter))
                            index.write("        <li>" + link + "\n")
                        index.write("    </ul>\n")
                        index.write("    </li>\n")
        if args.browse_profiles:
            import webbrowser
            webbrowser.open_new_tab("file://" + os.path.abspath(index_path))


def process(args):
    if args.catapult:
        write_catapult_trace(args)
    elif args.compare_stats_dirs:
        return compare_stats_dirs(args)
    elif args.set_csv_baseline is not None:
        return set_csv_baseline(args)
    elif args.compare_to_csv_baseline is not None:
        return compare_to_csv_baseline(args)
    elif args.incrementality:
        if args.paired:
            show_paired_incrementality(args)
        else:
            show_incrementality(args)
    elif args.lnt:
        write_lnt_values(args)
    elif args.evaluate:
        return evaluate(args)
    elif args.evaluate_delta:
        return evaluate_delta(args)
    elif args.render_profiles:
        return render_profiles(args)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verbose", action="store_true",
                        help="Report activity verbosely")
    parser.add_argument("--output", default="-",
                        type=argparse.FileType('w'),
                        help="Write output to file")
    parser.add_argument("--paired", action="store_true",
                        help="Process two dirs-of-stats-dirs, pairwise")
    parser.add_argument("--delta-pct-thresh", type=float, default=0.01,
                        help="Percentage change required to report")
    parser.add_argument("--delta-usec-thresh", type=int, default=100000,
                        help="Absolute delta on times required to report")
    parser.add_argument("--lnt-machine", type=str, default=platform.node(),
                        help="Machine name for LNT submission")
    parser.add_argument("--lnt-run-info", action='append', default=[],
                        type=lambda kv: kv.split("="),
                        help="Extra key=value pairs for LNT run-info")
    parser.add_argument("--lnt-machine-info", action='append', default=[],
                        type=lambda kv: kv.split("="),
                        help="Extra key=value pairs for LNT machine-info")
    parser.add_argument("--lnt-order", type=str,
                        default=str(int(time.time())),
                        help="Order for LNT submission")
    parser.add_argument("--lnt-tag", type=str, default="swift-compile",
                        help="Tag for LNT submission")
    parser.add_argument("--lnt-submit", type=str, default=None,
                        help="URL to submit LNT data to (rather than print)")
    parser.add_argument("--select-module",
                        default=[],
                        action="append",
                        help="Select specific modules")
    parser.add_argument("--group-by-module",
                        default=False,
                        action="store_true",
                        help="Group stats by module")
    parser.add_argument("--select-stat",
                        default=[],
                        action="append",
                        help="Select specific statistics")
    parser.add_argument("--select-stats-from-csv-baseline",
                        type=str, default=None,
                        help="Select statistics present in a CSV baseline")
    parser.add_argument("--exclude-timers",
                        default=False,
                        action="store_true",
                        help="only select counters, exclude timers")
    parser.add_argument("--sort-by-delta-pct",
                        default=False,
                        action="store_true",
                        help="Sort comparison results by delta-%%, not stat")
    parser.add_argument("--sort-descending",
                        default=False,
                        action="store_true",
                        help="Sort comparison results in descending order")
    parser.add_argument("--merge-by",
                        default="sum",
                        type=str,
                        help="Merge identical metrics by (sum|min|max)")
    parser.add_argument("--merge-timers",
                        default=False,
                        action="store_true",
                        help="Merge timers across modules/targets/etc.")
    parser.add_argument("--divide-by",
                        default=1,
                        metavar="D",
                        type=int,
                        help="Divide stats by D (to take an average)")
    parser.add_argument("--markdown",
                        default=False,
                        action="store_true",
                        help="Write output in markdown table format")
    parser.add_argument("--include-unchanged",
                        default=False,
                        action="store_true",
                        help="Include unchanged stats values in comparison")
    parser.add_argument("--close-regressions",
                        default=False,
                        action="store_true",
                        help="Close regression details in markdown")
    parser.add_argument("--github-emoji",
                        default=False,
                        action="store_true",
                        help="Add github-emoji indicators to markdown")
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--catapult", action="store_true",
                       help="emit a 'catapult'-compatible trace of events")
    modes.add_argument("--incrementality", action="store_true",
                       help="summarize the 'incrementality' of a build")
    modes.add_argument("--set-csv-baseline", type=str, default=None,
                       help="Merge stats from a stats-dir into a CSV baseline")
    modes.add_argument("--compare-to-csv-baseline", type=str, default=None,
                       metavar="BASELINE.csv",
                       help="Compare stats dir to named CSV baseline")
    modes.add_argument("--compare-stats-dirs",
                       action="store_true",
                       help="Compare two stats dirs directly")
    modes.add_argument("--lnt", action="store_true",
                       help="Emit an LNT-compatible test summary")
    modes.add_argument("--evaluate", type=str, default=None,
                       help="evaluate an expression of stat-names")
    modes.add_argument("--evaluate-delta", type=str, default=None,
                       help="evaluate an expression of stat-deltas")
    modes.add_argument("--render-profiles", action="store_true",
                       help="render any profiles to SVG flamegraphs")
    parser.add_argument("--flamegraph-script", type=str, default=None,
                        help="path to flamegraph.pl")
    parser.add_argument("--browse-profiles", action="store_true",
                        help="open web browser tabs with rendered profiles")
    parser.add_argument('remainder', nargs=argparse.REMAINDER,
                        help="stats-dirs to process")

    args = parser.parse_args()
    if len(args.remainder) == 0:
        parser.print_help()
        return 1
    try:
        return process(args)
    finally:
        args.output.close()


sys.exit(main())
