// Нативная Flash-оболочка вместо HTML index.html (WebKit/HTMLLoader мёртв в новом AIR).
// Грузит library.swf + client.swf в общий домен и поднимает игру. Пишет подробный
// лог в файл на Рабочем столе (TSO_log.txt) — переживает вылет, видно последнюю
// операцию перед падением. Чистый AS3 -> arm64 нативно.
package {
    import flash.display.Sprite;
    import flash.display.Loader;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.net.URLRequest;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ErrorEvent;
    import flash.events.UncaughtErrorEvent;
    import flash.system.LoaderContext;
    import flash.system.ApplicationDomain;
    import flash.system.Capabilities;
    import flash.desktop.NativeApplication;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.filesystem.File;
    import flash.filesystem.FileStream;
    import flash.filesystem.FileMode;

    [SWF(width="1280", height="800", backgroundColor="0x101010", frameRate="30")]
    public class TSOLoader extends Sprite {
        private var log:TextField;
        private var logFile:File;
        private var swmmo:*;
        private var ticks:int = 0;

        public function TSOLoader() {
            if (stage) init(); else addEventListener(Event.ADDED_TO_STAGE, init);
        }

        private function init(e:Event = null):void {
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;

            log = new TextField();
            log.width = 1276; log.height = 796;
            log.multiline = true; log.wordWrap = true; log.selectable = true;
            log.defaultTextFormat = new TextFormat("_sans", 13, 0x33FF66);
            addChild(log);

            // лог-файл на Рабочем столе (с откатом в хранилище приложения)
            try { logFile = File.desktopDirectory.resolvePath("TSO_log.txt"); }
            catch (err:Error) { logFile = File.applicationStorageDirectory.resolvePath("TSO_log.txt"); }
            try { var fs0:FileStream = new FileStream(); fs0.open(logFile, FileMode.WRITE); fs0.writeUTFBytes(""); fs0.close(); } catch (e2:Error) {}

            msg("=== TSO native loader v4 ===");
            msg("AIR " + Capabilities.version + " os=" + Capabilities.os + " cpu=" + Capabilities.cpuArchitecture);
            msg("stage " + stage.stageWidth + "x" + stage.stageHeight);

            loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, function (ev:UncaughtErrorEvent):void {
                var er:* = ev.error;
                msg("!! UNCAUGHT: " + (er is Error ? (Error(er).message + "\n" + Error(er).getStackTrace()) : String(er)));
            });

            // Игра закрывает окно/выходит без ошибки -> перехватываем И ОТМЕНЯЕМ,
            // чтобы окно осталось живым и игра догрузилась. Лог скажет, кто инициатор.
            try { NativeApplication.nativeApplication.autoExit = false; } catch (e4:Error) {}
            NativeApplication.nativeApplication.addEventListener(Event.EXITING, function (e:Event):void {
                try { e.preventDefault(); } catch (ee:Error) {}
                msg("!! EXITING intercepted & prevented");
            }, false, 1000);
            try {
                stage.nativeWindow.addEventListener(Event.CLOSING, function (e:Event):void {
                    try { e.preventDefault(); } catch (ee:Error) {}
                    msg("!! nativeWindow CLOSING intercepted & prevented");
                }, false, 1000);
                stage.nativeWindow.addEventListener(Event.CLOSE, function (e:Event):void { msg("!! nativeWindow CLOSE fired"); });
            } catch (e5:Error) { msg("nativeWindow hook err: " + e5.message); }

            msg("loading library.swf ...");
            loadSwf("library.swf", false, function (c:*):void {
                msg("library.swf OK. loading client.swf ...");
                loadSwf("client.swf", true, function (c2:*):void {
                    swmmo = c2;
                    msg("client.swf LOADED, on stage. Polling game state...");
                    addEventListener(Event.ENTER_FRAME, onTick);
                });
            });
        }

        private function onTick(e:Event):void {
            ticks++;
            if (ticks > 5 && ticks % 30 != 0) return;   // первые 5 кадров + затем раз в секунду
            try {
                var gf:* = swmmo.getDefinitionByName("globalFlash");
                var guiLoaded:* = "?";
                try { guiLoaded = gf.gui.GetDefaultGuiElementsLoaded(); } catch (e1:Error) {}
                msg("t" + (ticks / 30) + "s: globalFlash=" + (gf ? "yes" : "no") + " guiLoaded=" + guiLoaded +
                    " stageChildren=" + stage.numChildren);
            } catch (err:Error) {
                msg("t" + (ticks / 30) + "s probe: " + err.message);
            }
        }

        private function loadSwf(url:String, addToStage:Boolean, done:Function):void {
            var ctx:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            try { ctx.allowCodeImport = true; } catch (e:Error) {}
            var ld:Loader = new Loader();
            ld.contentLoaderInfo.addEventListener(Event.COMPLETE, function (e:Event):void {
                if (addToStage) { try { stage.addChildAt(ld.content, 0); } catch (err:Error) { msg("addChild err: " + err.message); } }
                try { done(ld.content); } catch (err:Error) { msg("post-load err: " + err.message + "\n" + err.getStackTrace()); }
            });
            ld.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function (e:IOErrorEvent):void { msg("!! IO ERROR " + url + ": " + e.text); });
            ld.contentLoaderInfo.addEventListener(ErrorEvent.ERROR, function (e:ErrorEvent):void { msg("!! ERR " + url + ": " + e.text); });
            // ВАЖНО: ловим необработанные ошибки ВНУТРИ загруженного SWF (ошибки игры
            // идут в её loaderInfo, а не в наш) — иначе игра падает "тихо".
            try {
                ld.contentLoaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, function (ev:UncaughtErrorEvent):void {
                    var er:* = ev.error;
                    msg("!! [" + url + "] UNCAUGHT: " + (er is Error ? (Error(er).message + "\n" + Error(er).getStackTrace()) : String(er)));
                });
            } catch (e3:Error) {}
            try { ld.load(new URLRequest(url), ctx); } catch (err:Error) { msg("!! load() threw " + url + ": " + err.message); }
        }

        private function msg(s:String):void {
            if (log) log.appendText(s + "\n");
            try {
                var fs:FileStream = new FileStream();
                fs.open(logFile, FileMode.APPEND);
                fs.writeUTFBytes(s + "\n");
                fs.close();
            } catch (e:Error) {}
        }
    }
}
