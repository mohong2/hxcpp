// SeiunEngine (hxcpp fork): the process entry point is also the last line of
// defence for a Haxe program.
//
// What used to happen here: a Haxe exception escaping __boot_all() or
// __hxcpp_main() was printed with the broken stack dump and then shown through
// MessageBoxA(utf8_text, "Error"). MessageBoxA decodes its input with the ANSI
// code page, so every Chinese message was mojibake, and on every non-Windows
// target the text went to a printf that a GUI-subsystem build throws away.
// hx::Boot() also sat OUTSIDE the try, so a failure during runtime bring-up
// (GC/thread/TLS init) reached the CRT's terminate() with no report at all.
//
// Now: hx::Boot() is inside the try, Dynamic/std::exception/... are all caught,
// and the single sink seiun_fatal_report() (source/backend/native_crash.inc)
// writes an UTF-8 report (with BOM) to crash/, leaves the one-shot pending
// marker for the next launch's recovery screen, and shows a MessageBoxW /
// TaskDialog with the report path before the process returns -1.
//
// The reporter symbol lives in the executable, i.e. in the same image as this
// header. It is still declared *optionally* so that any other project built
// against this fork keeps linking and keeps the legacy behaviour. "Optional"
// is spelled differently by every object format, and every spelling below is
// load-bearing - getting one wrong is not a warning, it is a failed link:
//
//   ELF    (gcc, clang)      weak *reference*: an undefined weak symbol
//                            resolves to 0 and the dispatch helper checks it.
//   Mach-O (Apple clang)     weak *definition*: an executable may not leave the
//                            symbol undefined at all - ld64 stops with
//                            "Undefined symbols for architecture arm64:
//                            _seiun_fatal_report, referenced from: _main" even
//                            for a plain .weak_reference - so the fallback is
//                            defined in this header and a strong definition in
//                            the application coalesces over it.
//   COFF   (MSVC, clang-cl)  /alternatename stub, with the decorated name.

#ifdef __cplusplus
#include <exception>
#endif
#if defined(__APPLE__) && defined(__cplusplus)
#include <cstdio>
#endif

#ifdef __cplusplus
extern "C" {
#endif
#if defined(_MSC_VER)
   // COFF: no syntax for a weak function reference, so the reference is emitted
   // strong and the /alternatename stub further down supplies a body when the
   // application defines none. (clang-cl defines _MSC_VER too and links with
   // link.exe/lld-link, which understand the same option.)
   void seiun_fatal_report(const char* kind, const char* msg, const char* detail);
#elif defined(__APPLE__)
   // Mach-O: attribute is on the definition (below), not on a reference.
   void seiun_fatal_report(const char* kind, const char* msg, const char* detail) __attribute__((weak));
#elif defined(__GNUC__) || defined(__clang__)
   void seiun_fatal_report(const char* kind, const char* msg, const char* detail) __attribute__((weak));
#  define SEIUN_FATAL_REPORT_IS_WEAK 1
#else
   void seiun_fatal_report(const char* kind, const char* msg, const char* detail);
#endif
#ifdef __cplusplus
}
#endif

// Dispatch helper shared by every catch below: a no-op when the linking
// application has no reporter (weak reference resolves to NULL).
static void seiun_top_level_report(const char* kind, const char* msg, const char* detail)
{
#ifdef SEIUN_FATAL_REPORT_IS_WEAK
   if (&seiun_fatal_report != 0)
#endif
      seiun_fatal_report(kind, msg, detail);
}

#ifdef HXCPP_DLL_IMPORT

   extern "C" EXPORT_EXTRA void __main__()
   {
     __boot_all();
     __hxcpp_main();
   }

#elif defined(HX_ANDROID) && !defined(HXCPP_EXE_LINK)

   // Java Main....
   #include <jni.h>
   #include <hx/Thread.h>
   #include <android/log.h>

   extern "C" EXPORT_EXTRA void hxcpp_main()
   {
      HX_TOP_OF_STACK
      try
      {
         hx::Boot();
         __boot_all();
         __hxcpp_main();
      }
      catch (Dynamic e)
      {
         __hx_dump_stack();
         const char* text = e==null() ? "null" : e->toString().__CStr();
         __android_log_print(ANDROID_LOG_ERROR, "Exception", "%s", text);
         // SeiunEngine: libhxcpp.so must not depend on the app, so the reporter
         // is referenced weakly here; when the app links one (it always does),
         // the boot-time exception also reaches crash/ instead of only logcat.
         seiun_top_level_report("haxe_uncaught_android", text, NULL);
      }
      catch (const std::exception& e)
      {
         __android_log_print(ANDROID_LOG_ERROR, "Exception", "C++: %s", e.what() ? e.what() : "?");
         seiun_top_level_report("cpp_exception_android", e.what(), NULL);
      }
      catch (...)
      {
         __android_log_print(ANDROID_LOG_ERROR, "Exception", "unknown native exception");
         seiun_top_level_report("unknown_exception_android", "Unknown native exception", NULL);
      }
      hx::SetTopOfStack((int *)0,true);
   }

   extern "C" EXPORT_EXTRA JNIEXPORT void JNICALL Java_org_haxe_HXCPP_main(JNIEnv * env)
   {
      hxcpp_main();
   }

#elif defined(HX_WINRT) && defined(__cplusplus_winrt)

   // WinRT is not a target of this engine; kept upstream so the fork stays a
   // drop-in replacement. No file-based report here (no writable cwd).
   #include <Roapi.h>
   [ Platform::MTAThread ]
   int main(Platform::Array<Platform::String^>^)
   {
      HX_TOP_OF_STACK
      RoInitialize(RO_INIT_MULTITHREADED);
      hx::Boot();
      try
      {
         __boot_all();
         __hxcpp_main();
      }
      catch (Dynamic e)
      {
         __hx_dump_stack();
         return -1;
      }
      return 0;
   }

#else

   #if defined(HX_WIN_MAIN) && !defined(_WINDOWS_)
   #ifndef HINSTANCE
   #define HINSTANCE void*
   #endif
   #ifndef LPSTR
   #define LPSTR char*
   #endif
   // windows.h is not pulled in here (hxcpp keeps this translation unit light),
   // so declare exactly what the legacy fallback below needs.
   #ifndef CP_UTF8
   #define CP_UTF8 65001
   #endif
   #ifndef MB_ERR_INVALID_CHARS
   #define MB_ERR_INVALID_CHARS 0x00000008
   #endif
   #ifndef MB_OK
   #define MB_OK 0x00000000
   #endif
   #ifndef MB_ICONERROR
   #define MB_ICONERROR 0x00000010
   #endif
   extern "C" int __stdcall MessageBoxW(void *,const wchar_t *,const wchar_t *,unsigned int);
   extern "C" int __stdcall MultiByteToWideChar(unsigned int,unsigned long,const char *,int,wchar_t *,int);
   #endif

#if defined(__APPLE__)
   // Fallback reporter for Mach-O, see the declaration above. Only reached when
   // the application defines no reporter of its own (the engine always does).
   // printf rather than MessageBoxW: drawing the dialog is the engine's job.
   extern "C" void seiun_fatal_report(const char* kind, const char* msg, const char* detail)
   {
      (void)kind;
      (void)detail;
      printf("Fatal error : %s\n", (msg != NULL && msg[0]) ? msg : "unknown fatal error");
   }
#elif defined(_MSC_VER)
   // MSVC cannot express a weak function reference. /alternatename makes the
   // linker bind seiun_fatal_report to this stub instead of failing when the
   // application does not define it (a real definition, as in the engine, wins
   // over the alternate name).
   extern "C" void seiun_fatal_report_stub(const char* kind, const char* msg, const char* detail)
   {
      (void)kind;
      const char* text = (msg != NULL && msg[0]) ? msg : "unknown fatal error";
#ifdef HX_WIN_MAIN
      wchar_t wide[2048];
      int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, wide, 2048);
      if (n <= 0) n = MultiByteToWideChar(CP_UTF8, 0, text, -1, wide, 2048);
      if (n > 0)
         MessageBoxW(0, wide, L"SeiunEngine - fatal error", MB_OK | MB_ICONERROR);
      else
         printf("Fatal error : %s\n", text);
#else
      printf("Fatal error : %s\n", text);
#endif
   }
   // /alternatename takes the *decorated* COFF name: x86 C functions carry a
   // leading underscore, x64/ARM64 ones do not. An undecorated name on x86 is
   // silently ignored and the link dies with LNK2019 _seiun_fatal_report.
#if defined(_M_IX86)
   #pragma comment(linker, "/alternatename:_seiun_fatal_report=_seiun_fatal_report_stub")
#else
   #pragma comment(linker, "/alternatename:seiun_fatal_report=seiun_fatal_report_stub")
#endif
#endif

   #if defined(TIZEN)
   extern "C" EXPORT_EXTRA int OspMain (int argc, char* pArgv[])
   {
   #elif defined(HX_WIN_MAIN)
   int __stdcall WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
   {
   #else

   extern int _hxcpp_argc;
   extern char **_hxcpp_argv;
   int main(int argc,char **argv)
   {
      _hxcpp_argc = argc;
      _hxcpp_argv = argv;
   #endif
      HX_TOP_OF_STACK
      try
      {
         // SeiunEngine: hx::Boot() moved INSIDE the try. It used to run before
         // it, so a failure during runtime bring-up (GC init, thread/TLS setup)
         // reached the CRT's terminate() without writing a single line.
         hx::Boot();
         __boot_all();
         __hxcpp_main();
      }
      catch (Dynamic e)
      {
          // Exception text is UTF-8 (the hxString::__CStr() contract); the
          // reporter converts it at the OS boundary only.
          // hxcpp's String is the global ::String (include/hxString.h), not hx::String.
          String message;
          String stackText;
          try
          {
              message = (e == null()) ? HX_CSTRING("null exception") : e->toString();
          }
          catch (...)
          {
              message = HX_CSTRING("(exception text unavailable)");
          }
          try
          {
              // A null Dynamic used to be dereferenced here (crash while
              // reporting a crash).
              auto customStack = (e == null()) ? String()
                  : e->__Field(HX_CSTRING("_hx_customStack"), HX_PROP_DYNAMIC).asString();
              if (::hx::IsNotNull(customStack))
              {
                  stackText = customStack;
                  printf("%s\n", customStack.__CStr());
              }
              else
              {
                  __hx_dump_stack();
              }
          }
          catch (...)
          {
              __hx_dump_stack();
          }

          seiun_top_level_report("haxe_uncaught", message.__CStr(), stackText.__CStr());
          return -1;
      }
      catch (const std::exception& e)
      {
          // C++ exceptions mean a failure below the Haxe layer (allocation,
          // out-of-range access inside hxcpp/the engine), so there is no Haxe
          // stack to print - only the exception text.
          const char* what = e.what();
          if (what == NULL) what = "(std::exception without what())";
          printf("Fatal C++ exception : %s\n", what);
          seiun_top_level_report("cpp_exception", what, NULL);
          return -1;
      }
      catch (...)
      {
          printf("Fatal unknown exception (not a Haxe Dynamic, not std::exception)\n");
          seiun_top_level_report("unknown_exception",
              "Unknown native exception (not a Haxe Dynamic and not std::exception)", NULL);
          return -1;
      }
      return 0;
   }
   #if 0
   }
   }
   #endif

#endif
