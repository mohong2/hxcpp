import haxe.ds.StringMap;
import haxe.ds.WeakMap;
import sys.thread.Thread;
import haxe.zip.Compress;
import haxe.zip.Uncompress;
import haxe.io.Bytes;

class Obj {
	public var id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

class Main {
	static var failures:Int = 0;

	static function check(name:String, cond:Bool) {
		if (cond)
			trace('ok: $name');
		else {
			trace('FAIL: $name');
			failures++;
		}
	}

	static function main() {
		// ========== 1. Lua color regression (must keep official 4.2.1 semantics) ==========
		check("parse 0xFFFF0000 == -65536", Std.parseInt("0xFFFF0000") == -65536);
		check("parse 0xffFF0000 == -65536", Std.parseInt("0xffFF0000") == -65536);
		check("parse 0xFFFFFFFF == -1", Std.parseInt("0xFFFFFFFF") == -1);
		check("parse 0xFF0000 == 16711680", Std.parseInt("0xFF0000") == 16711680);
		check("parse 0x7FFFFFFF", Std.parseInt("0x7FFFFFFF") == 0x7FFFFFFF);
		check("parse 0x80FF0000", Std.parseInt("0x80FF0000") == 0x80FF0000);
		check("parse 0x00800000", Std.parseInt("0x00800000") == 0x00800000);
		check("parse plain FF0000 (not hex, not decimal) -> null", Std.parseInt("FF0000") == null);
		check("parse 16711680", Std.parseInt("16711680") == 16711680);
		check("parse null-ish", Std.parseInt("zzz") == null);

		// ========== 2. allocation churn (nursery/generational/big-blocks/align) ==========
		var arr = new Array<Array<Int>>();
		for (i in 0...3000) {
			var inner = new Array<Int>();
			for (j in 0...400) inner.push((i * 31 + j) & 0xFFFF);
			arr.push(inner);
			if (i % 50 == 0) arr.shift(); // let some die -> GC work
		}
		var count:Int = 0;
		var sum:Float = 0;
		for (inner in arr) {
			count += inner.length;
			for (v in inner)
				sum += v;
		}
		check("alloc churn count", count == 2940 * 400);
		check("alloc churn all lengths intact", {
			var ok = true;
			for (inner in arr) if (inner.length != 400) ok = false;
			ok;
		});
		check("alloc churn last value", arr[arr.length - 1][0] == ((2999 * 31) & 0xFFFF));
		check("alloc churn sum finite", sum == sum);
		arr = null;

		// strings
		var s = "";
		for (i in 0...30000) s += Std.string(i % 10);
		check("string concat", s.length == 30000);

		// ========== 3. weak-key map (ephemeron semantics) ==========
		var wm = new WeakMap<Obj, String>();
		for (i in 0...200) {
			var o = new Obj(i);
			wm.set(o, 'value-$i');
		}
		// force GC pressure
		var junk = new Array<Dynamic>();
		for (i in 0...5000) junk.push({a: i, b: [i, i + 1, i + 2]});
		junk = null;
		var keep = new Obj(999);
		wm.set(keep, "keep-me");
		var kept:String = wm.get(keep);
		check("weak map keeps live key", kept == "keep-me");

		// ========== 4. threads ==========
		var main = Thread.current();
		var ts = new Array<Thread>();
		for (i in 0...8) {
			ts.push(Thread.create(() -> {
				var acc = 0;
				for (k in 0...50000) acc += k;
				main.sendMessage(acc);
			}));
		}
		var got = 0;
		for (t in ts) {
			var msg:Int = Thread.readMessage(true);
			if (msg > 0) got++;
		}
		check("8 threads done", got == 8);

		// ========== 5. zlib-ng round-trip ==========
		var data = Bytes.alloc(200000);
		for (i in 0...200000) data.set(i, (i * 7) & 0xFF);
		var compressed = Compress.run(data, 6);
		check("zlib compresses", compressed.length < data.length);
		var restored = Uncompress.run(compressed);
		check("zlib roundtrip", restored.compare(data) == 0);

		if (failures == 0)
			trace("ALL TESTS PASSED");
		else
			trace('$failures FAILURES');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
