/**
 * Bilingual (English / Simplified Chinese) message table for the hxcpp
 * command-line tool.
 *
 * Language selection order:
 *   1. SEIUN_LANG / HXCPP_LANG      (zh, zh-cn, en, ...)
 *   2. LANG / LANGUAGE              (unix convention)
 *   3. console code page            (936 / 950 / 54936 => Chinese Windows)
 *   4. English
 *
 * Encoding: this tool runs on Neko and writes raw UTF-8 bytes, so a console
 * whose code page is not UTF-8 (65001) would show mojibake. Neko cannot call
 * Win32 directly (neko.Lib.load only loads *.ndll), so the code page is read by
 * running `chcp` once; when it is not UTF-8 we fall back to ASCII + English.
 * SEIUN_UTF8=1 / SEIUN_ASCII=1 force the decision.
 */
class I18n
{
	public static var lang(default, null):String = "en";
	public static var unicodeOk(default, null):Bool = true;
	public static var codePage(default, null):Int = 0;

	static var tables:Map<String, Map<String, String>> = null;

	public static function init():Void
	{
		if (tables != null)
			return;

		codePage = detectCodePage();

		var asciiEnv = norm(Sys.getEnv("SEIUN_ASCII"));
		var utf8Env = norm(Sys.getEnv("SEIUN_UTF8"));
		if (isOn(asciiEnv))
			unicodeOk = false;
		else if (isOn(utf8Env))
			unicodeOk = true;
		else
			unicodeOk = (codePage <= 0) || (codePage == 65001);

		lang = pickLang();
		if (!unicodeOk)
			lang = "en";

		tables = buildTables();
	}

	/** Returns a one-line ASCII notice when localized output had to be disabled, else null. */
	public static function encodingHint():String
	{
		init();
		if (unicodeOk)
			return null;
		return t("encoding.hint", {cp: codePage});
	}

	public static function t(key:String, ?args:Dynamic):String
	{
		init();
		var table = tables.exists(lang) ? tables.get(lang) : tables.get("en");
		var text = table.exists(key) ? table.get(key) : null;
		if (text == null)
			text = tables.get("en").exists(key) ? tables.get("en").get(key) : key;
		if (args != null)
			text = subst(text, args);
		return text;
	}

	/** Display width, counting CJK code points as two cells (byte based, target safe). */
	public static function width(text:String):Int
	{
		var bytes = haxe.io.Bytes.ofString(text);
		var w = 0;
		var i = 0;
		while (i < bytes.length)
		{
			var b = bytes.get(i);
			if (b < 0x80) { w += 1; i += 1; }
			else if (b < 0xE0) { w += 1; i += 2; }
			else if (b < 0xF0) { w += 2; i += 3; }
			else { w += 2; i += 4; }
		}
		return w;
	}

	static function subst(text:String, args:Dynamic):String
	{
		var re = ~/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/g;
		return re.map(text, function(r:EReg) {
			var value:Dynamic = Reflect.field(args, r.matched(1));
			return value == null ? "" : Std.string(value);
		});
	}

	static function pickLang():String
	{
		for (name in ["SEIUN_LANG", "HXCPP_LANG", "LANG", "LANGUAGE"])
		{
			var value = norm(Sys.getEnv(name));
			if (value == null || value == "")
				continue;
			if (isChinese(value))
				return "zh";
			if (StringTools.startsWith(value, "en"))
				return "en";
		}

		// A console whose code page is 65001 (the "UTF-8 worldwide" option) says
		// nothing about the UI language, so ask Windows directly. Neko cannot call
		// Win32 (neko.Lib.load only loads *.ndll), so this is a cheap registry read.
		var locale = systemLocale();
		if (locale != null)
		{
			if (isChinese(locale))
				return "zh";
			if (StringTools.startsWith(locale, "en"))
				return "en";
		}

		if (codePage == 936 || codePage == 950 || codePage == 54936)
			return "zh";
		return "en";
	}

	static function systemLocale():String
	{
		if (Sys.systemName() != "Windows")
			return null;
		try
		{
			var process = new sys.io.Process("reg", ["query", "HKCU\\Control Panel\\International", "/v", "LocaleName"]);
			var output = "";
			try { output = process.stdout.readAll().toString(); } catch (e:Dynamic) {}
			process.close();
			var re = ~/LocaleName\s+REG_SZ\s+(\S+)/;
			if (re.match(output))
				return norm(re.matched(1));
		}
		catch (e:Dynamic) {}
		return null;
	}

	static function isChinese(value:String):Bool
	{
		return StringTools.startsWith(value, "zh") || value.indexOf("chinese") >= 0
			|| value.indexOf("hans") >= 0 || value.indexOf("chs") >= 0;
	}

	static function detectCodePage():Int
	{
		if (Sys.systemName() != "Windows")
			return 0;
		try
		{
			var process = new sys.io.Process("chcp", []);
			var output = "";
			try { output = process.stdout.readAll().toString(); } catch (e:Dynamic) {}
			process.close();
			var re = ~/([0-9]{3,5})/;
			if (re.match(output))
				return Std.parseInt(re.matched(1));
		}
		catch (e:Dynamic) {}
		return 0;
	}

	static function isOn(value:String):Bool
	{
		return value == "1" || value == "true" || value == "yes" || value == "on";
	}

	static function norm(value:String):String
	{
		return value == null ? null : value.toLowerCase();
	}

	static function buildTables():Map<String, Map<String, String>>
	{
		var en = new Map<String, String>();
		en.set("encoding.hint", "(console code page {cp} is not UTF-8: using ASCII + English output. Run \"chcp 65001\" to enable Chinese/Unicode.)");
		en.set("progress.header", "Compiling group {i}/{n}: {id} ({files} files, overall {pct}%, elapsed {elapsed})");
		en.set("progress.bar", "[{bar}] {pct}% {done}/{total} ETA {eta}");
		en.set("progress.groupdone", "  group {i}/{n} done: {files} files, overall {pct}%, elapsed {elapsed}, ETA {eta}");
		en.set("progress.summary", "Compiled {files} files in {elapsed} ({groups} groups)");
		en.set("progress.nothing", "Nothing to compile: everything is up to date");
		en.set("progress.file", "[{index}/{total}] {file}");
		en.set("progress.failed", "== compile failed: {file} ==");
		en.set("progress.filelist", "{count} files recompiled - full list: {path}");

		var zh = new Map<String, String>();
		zh.set("encoding.hint", en.get("encoding.hint"));
		zh.set("progress.header", "正在编译第 {i}/{n} 组: {id} ({files} 个文件, 总进度 {pct}%, 已用 {elapsed})");
		zh.set("progress.bar", "[{bar}] {pct}% {done}/{total} 剩余 {eta}");
		zh.set("progress.groupdone", "  第 {i}/{n} 组完成: {files} 个文件, 总进度 {pct}%, 已用 {elapsed}, 剩余 {eta}");
		zh.set("progress.summary", "编译完成: {files} 个文件, 用时 {elapsed} ({groups} 组)");
		zh.set("progress.nothing", "无需编译: 所有目标文件都是最新的");
		zh.set("progress.file", "[{index}/{total}] {file}");
		zh.set("progress.failed", "== 编译失败: {file} ==");
		zh.set("progress.filelist", "本次重新编译 {count} 个文件 - 完整清单: {path}");

		var tables = new Map<String, Map<String, String>>();
		tables.set("en", en);
		tables.set("zh", zh);
		return tables;
	}
}
