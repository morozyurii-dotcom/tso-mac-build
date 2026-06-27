// Нативная Flash-оболочка вместо HTML index.html (WebKit/HTMLLoader мёртв в новом AIR).
// Делает то же, что делал index.html: грузит library.swf + client.swf в общий
// домен приложения и поднимает игру на сцену. Чистый AS3 -> работает на arm64 нативно.
// На экран выводит лог/ошибки, чтобы видеть, доходит ли игра до своего экрана входа.
package {
    import flash.display.Sprite;
    import flash.display.Loader;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.net.URLRequest;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.UncaughtErrorEvent;
    import flash.system.LoaderContext;
    import flash.system.ApplicationDomain;
    import flash.text.TextField;
    import flash.text.TextFormat;

    [SWF(width="1024", height="768", backgroundColor="0x101010", frameRate="30")]
    public class TSOLoader extends Sprite {
        private var log:TextField;
        private var swmmo:*;

        public function TSOLoader() {
            if (stage) init(); else addEventListener(Event.ADDED_TO_STAGE, init);
        }

        private function init(e:Event = null):void {
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;

            log = new TextField();
            log.width = 1004; log.height = 760;
            log.multiline = true; log.wordWrap = true; log.selectable = true;
            log.defaultTextFormat = new TextFormat("_sans", 14, 0x33FF66);
            addChild(log);
            msg("TSO native loader (AS3, arm64). Stage " + stage.stageWidth + "x" + stage.stageHeight);

            loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, function(ev:UncaughtErrorEvent):void {
                var er:* = ev.error;
                msg("!! UNCAUGHT: " + (er is Error ? (Error(er).message + "\n" + Error(er).getStackTrace()) : String(er)));
            });

            msg("loading library.swf ...");
            loadSwf("library.swf", false, function(libContent:*):void {
                msg("library.swf OK. loading client.swf ...");
                loadSwf("client.swf", true, function(clientContent:*):void {
                    swmmo = clientContent;
                    msg("client.swf LOADED and added to stage. Waiting for game to render...");
                });
            });
        }

        private function loadSwf(url:String, addToStage:Boolean, done:Function):void {
            var ctx:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            try { ctx.allowCodeImport = true; } catch (err:Error) {}
            var ld:Loader = new Loader();
            ld.contentLoaderInfo.addEventListener(Event.COMPLETE, function(e:Event):void {
                if (addToStage) {
                    try { stage.addChildAt(ld.content, 0); } catch (err:Error) { msg("addChild error: " + err.message); }
                }
                try { done(ld.content); } catch (err:Error) { msg("post-load error: " + err.message + "\n" + err.getStackTrace()); }
            });
            ld.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
                msg("!! IO ERROR loading " + url + ": " + e.text);
            });
            try {
                ld.load(new URLRequest(url), ctx);
            } catch (err:Error) {
                msg("!! load() threw for " + url + ": " + err.message);
            }
        }

        private function msg(s:String):void {
            if (log) log.appendText(s + "\n");
        }
    }
}
