package utest;

import haxe.rtti.Meta;

/**
* @todo add documentation
*/
class TestFixture<T> {
	public var target(default, null)   : T;
	public var method(default, null)   : String;
	public var setup(default, null)    : String;
	public var teardown(default, null) : String;
	#if testSelected
	public var isSelected(default, null):Bool;
	#end
	public function new(target : T, method : String, ?setup : String, ?teardown : String) {
		this.target   = target;
		this.method   = method;
		this.setup    = setup;
		this.teardown = teardown;
		#if testSelected
		var meta = Meta.getFields(Type.getClass(target));
		isSelected = {
			var t = this.method;
			if (Reflect.hasField(meta, this.method)) {
				var f = Reflect.field(meta, this.method);
				if (Reflect.hasField(f, "select")) true else false;
			} else false;
		}
		#end
	}

	function checkMethod(name : String, arg : String) {
		var field = Reflect.field(target, name);
		if(field == null)              throw arg + " function " + name + " is not a field of target";
		if(!Reflect.isFunction(field)) throw arg + " function " + name + " is not a function";
	}
}