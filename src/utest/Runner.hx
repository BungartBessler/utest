package utest;

import haxe.rtti.Meta;
import utest.Dispatcher;

/**
* The Runner class performs a set of tests. The tests can be added using addCase or addFixtures.
* Once all the tests are register they are axecuted on the run() call.
* Note that Runner does not provide any visual output. To visualize the test results use one of
* the classes in the utest.ui package.
* @todo complete documentation
* @todo AVOID CHAINING METHODS (long chains do not work properly on IE)
*/
class Runner {
	var fixtures(default, null) : Array<TestFixture<Dynamic>>;

	/**
	* Event object that monitors the progress of the runner.
	*/
	public var onProgress(default, null) : Dispatcher<{ result : TestResult, done : Int, totals : Int }>;
	/**
	* Event object that monitors when the runner starts.
	*/
	public var onStart(default, null)    : Dispatcher<Runner>;
	/**
	* Event object that monitors when the runner ends. This event takes into account async calls
	* performed during the tests.
	*/
	public var onComplete(default, null) : Dispatcher<Runner>;
	/**
	* The number of fixtures registered.
	*/
	public var length(default, null)      : Int;
	/**
	* Instantiates a Runner onject.
	*/
	public function new() {
		fixtures   = new Array();
		onProgress = new Dispatcher();
		onStart    = new Dispatcher();
		onComplete = new Dispatcher();
		length = 0;
	}

	/**
	* Adds a new test case.
	* @param	test: must be a not null object
	* @param	setup: string name of the setup function (defaults to "setup")
	* @param	teardown: string name of the teardown function (defaults to "teardown")
	* @param	prefix: prefix for methods that are tests (defaults to "test")
	* @param	pattern: a regular expression that discriminates the names of test
	* 			functions; when set,  the prefix parameter is meaningless
	*/
	public function addCase(test : Dynamic, setup = "setup", teardown = "teardown", prefix = "test", ?pattern : EReg) {
		#if testSelectedCase
		var meta = Meta.getType(Type.getClass(test));
		var isSelected = if (Reflect.hasField(meta, "select")) true else false;
		if (!isSelected) return;
		#end

		if(!Reflect.isObject(test)) throw "can't add a null object as a test case";
		if(!isMethod(test, setup))
			setup = null;
		if(!isMethod(test, teardown))
			teardown = null;
		var fields = Type.getInstanceFields(Type.getClass(test));
		if(pattern == null) {
			for(field in fields) {
				if(!StringTools.startsWith(field, prefix)) continue;
				if(!isMethod(test, field)) continue;
				addFixture(new TestFixture(test, field, setup, teardown));
			}
		} else {
			for(field in fields) {
				if(!pattern.match(field)) continue;
				if(!isMethod(test, field)) continue;
				addFixture(new TestFixture(test, field, setup, teardown));
			}
		}
	}

	public function addFixture(fixture : TestFixture<Dynamic>) {
		#if testSelected
		if (!fixture.isSelected) {
			return;
		}
		#end
		fixtures.push(fixture);
		length++;
	}

	public function getFixture(index : Int) {
		return fixtures[index];
	}

	function isMethod(test : Dynamic, name : String) {
		try {
			return Reflect.isFunction(Reflect.field(test, name));
		} catch(e : Dynamic) {
			return false;
		}
	}
#if (php || neko)
	public function run() {
		onStart.dispatch(this);
		for (i in 0...fixtures.length)
		{
			var h = runFixture(fixtures[i]);
			onProgress.dispatch({ result : TestResult.ofHandler(h), done : i+1, totals : length });
		}
		onComplete.dispatch(this);
	}

	function runFixture(fixture : TestFixture<Dynamic>) {
		var handler = new TestHandler(fixture);
		handler.execute();
		return handler;
	}
#else
	var pos : Int;
	public function run() {
		pos = 0;
		onStart.dispatch(this);
		runNext();
	}

	function runNext() {
		if(fixtures.length > pos) 
			runFixture(fixtures[pos++]);
		else
			onComplete.dispatch(this);
	}

	function runFixture(fixture : TestFixture<Dynamic>) {
		var handler = new TestHandler(fixture);

		handler.onComplete.add(testComplete);
		handler.execute();
	}

	function testComplete(h : TestHandler<Dynamic>) {
		var result = TestResult.ofHandler(h);
		onProgress.dispatch({ result : result, done : pos, totals : length });
		#if stopOnFirstError 
		if (!result.allOk()) {
			onComplete.dispatch(this);		
		} else {
			runNext();
		}
		#else
		runNext();
		#end
		
		
	}
#end
}