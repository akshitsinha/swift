import Seas

@available(Arctic) // expected-warning {{unrecognized platform name 'Arctic'}}
func availableInArctic() { }

@available(Mediterranean)
func availableInMediterranean() { }

func testOtherClangDecls() {
  available_in_baltic()
}
