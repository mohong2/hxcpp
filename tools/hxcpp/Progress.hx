/**
 * Single-line build progress for the hxcpp command-line tool.
 *
 * Replaces the previous "one line per compiled file" output with a bar that is
 * redrawn in place:
 *
 *   [############------------]  47% 1281/2726 ETA 3m41s
 *
 * Modes (SEIUN_PROGRESS / HXCPP_PROGRESS):
 *   bar   redraw one line in place (default, except in CI)
 *   line  print one line every 10% - best for log files and CI
 *   off   no progress output at all
 * `verbose` keeps the old per-file lines instead.
 */
class Progress
{
	public static var enabled:Bool = false;
	public static var barMode:Bool = true;
	public static var drawn(default, null):Bool = false;

	static var inited:Bool = false;
	static var ascii:Bool = true;
	static var total:Int = 0;
	static var done:Int = 0;
	static var groups:Int = 0;
	static var startTime:Float = 0;
	static var lastDraw:Float = -1;
	static var lastPct:Int = -1;
	static var lastLen:Int = 0;

	static inline var BAR_WIDTH = 24;
	static inline var DRAW_INTERVAL = 0.1;

	public static function init():Void
	{
		if (inited)
			return;
		inited = true;

		I18n.init();
		ascii = !I18n.unicodeOk;

		if (Log.quiet || Log.verbose)
			return;

		var mode = norm(Sys.getEnv("SEIUN_PROGRESS"));
		if (mode == null || mode == "")
			mode = norm(Sys.getEnv("HXCPP_PROGRESS"));

		if (mode == "off" || mode == "0" || mode == "false" || mode == "none")
			return;

		if (mode == "bar")
			barMode = true;
		else if (mode == "line")
			barMode = false;
		else
			barMode = !runningInCI();

		enabled = true;

		var hint = I18n.encodingHint();
		if (hint != null)
			Log.println(hint);
	}

	static function runningInCI():Bool
	{
		for (name in ["CI", "GITHUB_ACTIONS", "TF_BUILD", "BUILDKITE", "GITLAB_CI", "JENKINS_URL", "APPVEYOR"])
			if (Sys.getEnv(name) != null)
				return true;
		return false;
	}

	public static function plan(totalFiles:Int, groupCount:Int):Void
	{
		total = totalFiles;
		groups = groupCount;
		done = 0;
		lastPct = -1;
		startTime = Sys.time();
		lastDraw = startTime;
	}

	public static function nothingToDo():Void
	{
		if (!enabled)
			return;
		Log.println(I18n.t("progress.nothing"));
	}

	public static function startGroup(i:Int, n:Int, id:String, files:Int, offset:Int):Void
	{
		if (!enabled || files <= 0)
			return;
		dropLine();
		var pct = total > 0 ? Math.floor(offset * 100 / total) : 0;
		Log.println(I18n.t("progress.header", {i: i, n: n, id: id, files: files, pct: pct, elapsed: fmt(Sys.time() - startTime)}));
	}

	public static function fileDone():Void
	{
		if (!enabled)
			return;
		done++;
		maybeDraw();
	}

	public static function endGroup(i:Int, n:Int, files:Int, offset:Int):Void
	{
		if (!enabled || files <= 0)
			return;
		dropLine();
		var reached = offset + files;
		if (total > 0 && reached > total)
			reached = total;
		var pct = total > 0 ? Math.floor(reached * 100 / total) : 100;
		var elapsed = Sys.time() - startTime;
		Log.println(I18n.t("progress.groupdone", {i: i, n: n, files: files, pct: pct, elapsed: fmt(elapsed), eta: fmt(eta(elapsed, reached))}));
	}

	public static function finish(totalFiles:Int, groupCount:Int, start:Float):Void
	{
		if (!enabled || totalFiles <= 0)
			return;
		dropLine();
		Log.println(I18n.t("progress.summary", {files: totalFiles, elapsed: fmt(Sys.time() - start), groups: groupCount}));
	}

	/** A compiler failed: get out of the way so its diagnostics are readable. */
	public static function errorOccurred():Void
	{
		if (drawn)
			dropLine();
		barMode = false;
	}

	/** Erase the in-place bar line; safe to call from any thread, and from Log. */
	public static function dropLine():Void
	{
		if (!drawn)
			return;
		raw("\r" + spaces(lastLen) + "\r");
		drawn = false;
		lastLen = 0;
	}

	static function maybeDraw():Void
	{
		var pct = total > 0 ? Math.floor(done * 100 / total) : 100;
		if (pct > 100)
			pct = 100;

		if (barMode)
		{
			var now = Sys.time();
			if (done < total && lastDraw > 0 && now - lastDraw < DRAW_INTERVAL)
				return;
			lastDraw = now;
			var text = barText(pct);
			var textWidth = I18n.width(text);
			var pad = lastLen > textWidth ? lastLen - textWidth : 0;
			raw("\r" + text + spaces(pad));
			lastLen = textWidth;
			drawn = true;
		}
		else
		{
			if (done < total && pct < lastPct + 10)
				return;
			lastPct = pct;
			dropLine();
			Log.println("  " + barText(pct));
		}
	}

	static function barText(pct:Int):String
	{
		var filled = Math.floor(BAR_WIDTH * pct / 100);
		var bar = "";
		for (i in 0...BAR_WIDTH)
			bar += (i < filled) ? (ascii ? "#" : "\u2588") : (ascii ? "-" : "\u2591");
		var elapsed = Sys.time() - startTime;
		return I18n.t("progress.bar", {bar: bar, pct: pct, done: done, total: total, eta: fmt(eta(elapsed, done))});
	}

	static function eta(elapsed:Float, doneCount:Int):Float
	{
		if (doneCount <= 0 || total <= doneCount)
			return 0;
		return elapsed * (total - doneCount) / doneCount;
	}

	public static function fmt(seconds:Float):String
	{
		var s = Math.round(seconds);
		if (s < 60)
			return s + "s";
		var m = Math.floor(s / 60);
		var r = s - m * 60;
		if (m < 60)
			return m + "m" + (r < 10 ? "0" : "") + r + "s";
		var h = Math.floor(m / 60);
		var rest = m - h * 60;
		return h + "h" + (rest < 10 ? "0" : "") + rest + "m";
	}

	static function spaces(count:Int):String
	{
		return count <= 0 ? "" : StringTools.lpad("", " ", count);
	}

	static function raw(text:String):Void
	{
		if (Log.printMutex != null)
			Log.printMutex.acquire();
		try { Sys.print(text); } catch (e:Dynamic) {}
		if (Log.printMutex != null)
			Log.printMutex.release();
	}

	static function norm(value:String):String
	{
		return value == null ? null : value.toLowerCase();
	}
}
