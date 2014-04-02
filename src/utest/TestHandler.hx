package utest;

import haxe.rtti.Meta;
import scuts.core.Promises;
import utest.Assertation;

/**
* @todo add documentation
*/
class TestHandler<T> {
	private static inline var POLLING_TIME = 10;
	public var results(default, null) : List<Assertation>;
	public var fixture(default, null) : TestFixture<T>;
	var asyncStack : List<Dynamic>;

	public var onTested(default, null) : Dispatcher<TestHandler<T>>;
	public var onTimeout(default, null) : Dispatcher<TestHandler<T>>;
	public var onComplete(default, null) : Dispatcher<TestHandler<T>>;

	var meta : Dynamic<Dynamic<Array<Dynamic>>>;



	public function new(fixture : TestFixture<T>) {
		if(fixture == null) throw "fixture argument is null";
		this.fixture  = fixture;
		results       = new List();
		asyncStack    = new List();
		onTested   = new Dispatcher();
		onTimeout  = new Dispatcher();
		onComplete = new Dispatcher();
		meta = Meta.getFields(Type.getClass(fixture.target));


	}

	public function execute() {

		function execFixture (call:Bool) {



			var asyncMethod = {
				var t = fixture.method;
				if (Reflect.hasField(meta, fixture.method)) {
					var f = Reflect.field(meta, fixture.method);
					if (Reflect.hasField(f, "async")) true else false;
				} else false;
			}

			try {

				if (asyncMethod)
					executeMethod(fixture.method,true)
				else
					executeMethod(fixture.method);
			} catch (e : Dynamic) {
				printStack(e);
				results.add(Error(e, exceptionStack()));
			}
			if (call) {
				checkTested();
			}
		}


		try {

			#if debug
			trace("running " + fixture.method + "...");
			#end

			var asyncSetup = {
				var t = fixture.target;
				if (Reflect.hasField(meta, fixture.setup)) {
					var f = Reflect.field(meta, fixture.setup);
					if (Reflect.hasField(f, "async")) true else false;
				} else false;
			}



			if (asyncSetup) {
				var p:Promise<Dynamic> = executeMethod(fixture.setup, true);
				Promises.onComplete(p, function (c) {
					switch (c) {
						case Failure(f):
							trace(f);
							results.add(SetupError(f, exceptionStack()));
						case _:
					}
					execFixture(true);
				});

			} else {
				execFixture(false);
			}

		} catch(e : Dynamic) {
			printStack(e);
			results.add(SetupError(e, exceptionStack()));
			checkTested();
		}


	}

	static function exceptionStack(pops = 2)
	{
		var stack = haxe.CallStack.exceptionStack();
		while (pops-- > 0)
		{
			stack.pop();
		}
		return stack;
	}

	function checkTested() {
#if (flash || js)
		if(expireson == null || asyncStack.length == 0) {
			tested();
		} else if(#if notimeout false && #end haxe.Timer.stamp() > expireson) {
			timeout();
		} else {
			haxe.Timer.delay(checkTested, POLLING_TIME);
		}
#else
		if(asyncStack.length == 0)
			tested();
		else
			timeout();
#end
	}

	public var expireson(default, null) : Null<Float>;
	public function setTimeout(timeout : Int) {
		var newexpire = haxe.Timer.stamp() + timeout/1000;
		expireson = (expireson == null) ? newexpire : (newexpire > expireson ? newexpire : expireson);
	}

	function bindHandler() {
		Assert.results     = this.results;
		Assert.createAsync = this.addAsync;
		Assert.createEvent = this.addEvent;
	}

	function unbindHandler() {
		Assert.results     = null;
		Assert.createAsync = function(f, ?t){ return function(){}};
		Assert.createEvent = function(f, ?t){ return function(e){}};
	}

	function printStack (e) {
		#if (debug && !hideStackTrace)
		if (e.stack != null) {
			trace(e.stack);
		} else {
			trace(Std.string(untyped __new__("Error").stack));
		}
		#end
	}

	/**
	* Adds a function that is called asynchronously.
	*
	* Example:
	* <pre>
	* var fixture = new TestFixture(new TestClass(), "test");
	* var handler = new TestHandler(fixture);
	* var flag = false;
	* var async = handler.addAsync(function() {
	*   flag = true;
	* }, 50);
	* handler.onTimeout.add(function(h) {
	*   trace("TIMEOUT");
	* });
	* handler.onTested.add(function(h) {
	*   trace(flag ? "OK" : "FAILED");
	* });
	* haxe.Timer.delay(function() async(), 10);
	* handler.execute();
	* </pre>
	* @param	f, the function that is called asynchrnously
	* @param	timeout, the maximum time to wait for f() (default is 250)
	* @return	returns a function closure that must be executed asynchrnously
	*/

	public function addAsync(f : Void->Void, timeout = 250) {
		if (null == f)
			f = function() { }
		asyncStack.add(f);
		var handler = this;
		setTimeout(timeout);
		return function() {
			if(!handler.asyncStack.remove(f)) {
				handler.results.add(AsyncError("method already executed", []));
				return;
			}
			try {
				handler.bindHandler();
				f();
			} catch(e : Dynamic) {

				printStack(e);

				handler.results.add(AsyncError(e, exceptionStack(0))); // TODO check the correct number of functions is popped from the stack
			}
		};
	}

	public function addEvent<EventArg>(f : EventArg->Void, timeout = 250) {
		asyncStack.add(f);
		var handler = this;
		setTimeout(timeout);
		return function(e : EventArg) {
			if(!handler.asyncStack.remove(f)) {
				handler.results.add(AsyncError("event already executed", []));
				return;
			}
			try {
				handler.bindHandler();
				f(e);
			} catch(e : Dynamic) {
				printStack(e);
				handler.results.add(AsyncError(e, exceptionStack(0))); // TODO check the correct number of functions is popped from the stack
			}
		};
	}

	function executeMethod(name : String, async:Bool = false, asyncTimeout:Int = 1000):Dynamic {

		if(name == null) return null;
		bindHandler();
		return if (async) {
			var p = Reflect.callMethod(fixture.target, Reflect.field(fixture.target, name), []);

			var f = addAsync(function () {}, asyncTimeout);

			if (!Std.is(p, Promise)) {
				throw "async method should return promise";
			}
			var prom = Promises.onComplete(p, function (x) {
				switch (x) {
					case Failure(f):
						#if debug
						trace(f);
						#end
						Assert.fail("The test returned a promise which failed to complete with failure:\n-----------------------\n" + f + "\n-----------------------\n");
					case _:
				}
				f();
			});

			prom;
		} else {
			var p = Reflect.callMethod(fixture.target, Reflect.field(fixture.target, name), []);
			if (Std.is(p, Promise)) {
				trace('method $name returning promises should be marked as async.');
			}
			p;
		}
	}

	function tested() {
		if(results.length == 0)
			results.add(Warning("no assertions"));
		onTested.dispatch(this);
		completed();
	}

	function timeout() {
		results.add(TimeoutError(asyncStack.length, []));
		onTimeout.dispatch(this);
		completed();
	}

	function completed() {
		function handler () {
			unbindHandler();
			onComplete.dispatch(this);
		}
		try {

			var async = {
				var t = fixture.target;
				if (Reflect.hasField(meta, fixture.teardown)) {
					var f = Reflect.field(meta, fixture.teardown);
					if (Reflect.hasField(f, "async")) true else false;
				} else false;
			}

			if (async) {
				var p : Promise<Dynamic> = executeMethod(fixture.teardown, true);

				Promises.onComplete(p, function (c) {
					switch (c) {
						case Failure(f):
							trace(f);
							results.add(TeardownError(f, exceptionStack(2)));
						case Success(_):
					}
					handler();
				});


			} else {
				executeMethod(fixture.teardown);
				handler();
			}
		} catch(e : Dynamic) {
			printStack(e);
			results.add(TeardownError(e, exceptionStack(2))); // TODO check the correct number of functions is popped from the stack
		}

	}
}