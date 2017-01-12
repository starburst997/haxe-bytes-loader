package bytesloader;

import haxe.io.Bytes;
import haxe.Json;

#if openfl
  import openfl.events.Event;
  import openfl.events.ProgressEvent;
  import openfl.events.HTTPStatusEvent;
  import openfl.events.ErrorEvent;
  import openfl.events.AsyncErrorEvent;
  import openfl.events.SecurityErrorEvent;
  import openfl.events.IOErrorEvent;
  import openfl.net.URLLoader;
  import openfl.net.URLLoaderDataFormat;
  import openfl.net.URLRequest;
  import openfl.utils.ByteArray;
#elseif flash
  import flash.events.Event;
  import flash.events.ProgressEvent;
  import flash.events.HTTPStatusEvent;
  import flash.events.ErrorEvent;
  import flash.events.AsyncErrorEvent;
  import flash.events.SecurityErrorEvent;
  import flash.events.IOErrorEvent;
  import flash.net.URLLoader;
  import flash.net.URLLoaderDataFormat;
  import flash.net.URLRequest;
  import flash.utils.ByteArray;
#elseif js
  import js.html.Event;
  import js.html.ProgressEvent;
  import js.html.XMLHttpRequest;
#end

// Use those public types
typedef BytesLoader = Loader<Bytes>;
typedef StringLoader = Loader<String>;
typedef JsonLoader = Loader<Dynamic>;

typedef BytesLoaders = Loaders<Bytes>;
typedef StringLoaders = Loaders<String>;
typedef JsonLoaders = Loaders<Dynamic>;

typedef BytesLoaderParams = CallbacksWithURL<Bytes>;
typedef StringLoaderParams = CallbacksWithURL<String>;
typedef JsonLoaderParams = CallbacksWithURL<Dynamic>;

// Callbacks arguments
private typedef Callbacks<T> =
{
  @:optional var complete:T->Void;
  @:optional var progress:Float->Void;
  @:optional var error:String->Void;
}

private typedef FinalCallbacks =
{
  @:optional var complete:Bool->Void;
  @:optional var progress:Float->Void;
  @:optional var error:String->Void;
}

private typedef CallbacksWithURL<T> =
{
  > Callbacks<T>,
  var url:String;
}

/**
 * Load multiple loader chained together
 */
@:generic
private class Loaders<T>
{
  // Keep all loaders
  private var loaders = new Array<Loader<T>>();

  // Constructor
  public function new()
  {
    // Not much to do here
  }

  // Load multiple loader, keep track of progress and final callback
  public function load( callbacks:Array<CallbacksWithURL<T>>, callback:FinalCallbacks = null )
  {
    var _loaders = new Array<Loader<T>>();
    var counter = callbacks.length;
    var completed = 0;
    var done = false; // if we get an error during loop, stop all...

    // Remove reference from array
    function _clean()
    {
      for ( loader in _loaders )
      {
        loader.clean();
        loaders.remove(loader);
      }

      trace("Loaders:", loaders.length);
    }

    // Check all files to load
    for ( params in callbacks )
    {
      if ( done ) break; // Skip if we got an error

      // Save local reference
      var complete = params.complete;
      var progress = params.progress;
      var error = params.error;

      // Create new loader
      var loader = new Loader<T>();

      loader.init(params.url, {
        complete: function(_value)
        {
          // Loader completed loading the file
          if ( complete != null ) complete(_value);
          loaders.remove(loader);

          // If there is no value, an error happened, diregard...
          if (_value != null)
          {
            completed++;

            if ( !done && (completed >= counter) )
            {
              if ( callback.complete != null )
              {
                callback.complete(false);
                _clean();
              }
            }
          }
        }, progress: function(_percent)
        {
          // Handle progress events
          if ( progress != null ) progress(_percent);
          if ( callback.progress != null )
          {
            var percent = 0.0;
            for ( _loader in _loaders ) percent += _loader.progress;
            percent = percent / counter;

            callback.progress(percent);
          }
        }, error: function(_error)
        {
          // When there is an error, stop futher loading...
          if ( !done )
          {
            done = true;

            // Call complete with error
            if ( callback.complete != null ) callback.complete(true);

            // Clean what's left
            _clean();
          }

          if ( error != null ) error(_error);
          if ( callback.error != null ) callback.error(_error);
        }
      });

      // If we got an error, don't go any further
      if ( !done )
      {
        loaders.push(loader);
        _loaders.push(loader);
      }
    }
  }
}

/**
 * Generic loader
 */
@:generic
private class Loader<T>
{
  // Progress
  public var progress:Float = 0.0;

  // Keep url
  var url:String;

  // Return a string instead
  var isText:Bool = false;

  // Return a JSON instead
  var isJson:Bool = false;

  // Callbacks
  var completeHandler:T->Void;
  var errorHandler:String->Void;
  var progressHandler:Float->Void;

  // Create new loader
  public function new(url:String = null, callbacks:Callbacks<T> = null)
  {
    isText = !Std.is(this, BytesLoader);
    if ( isText )
    {
      isJson = Std.is(this, JsonLoader);
    }

    if ( url != null ) init(url, callbacks);
  }

  // Init
  public function init(url:String, callbacks:Callbacks<T>)
  {
    trace("BytesLoader:", url);

    this.progress = 0.0;

    this.url = url;
    this.completeHandler = callbacks.complete;
    this.errorHandler = callbacks.error;
    this.progressHandler = callbacks.progress;

    _load();
  }

  // Cancel request
  public function cancel()
  {
    trace("Not implemented...");
  }

  #if (openfl || flash)
  private var loader:URLLoader;
  private function _load()
  {
    // OpenFL / Flash are the same, just different imports
    loader = new URLLoader();
    loader.dataFormat = isText ? URLLoaderDataFormat.TEXT : URLLoaderDataFormat.BINARY;

    loader.addEventListener(ProgressEvent.PROGRESS, _progressHandler, false, 0, true);
    loader.addEventListener(Event.COMPLETE, _completeHandler, false, 0, true);

    // Status
    loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, _statusHandler, false, 0, true);

    // Errors
    loader.addEventListener(ErrorEvent.ERROR, _errorHandler, false, 0, true);
    loader.addEventListener(AsyncErrorEvent.ASYNC_ERROR, _errorHandler, false, 0, true);
    loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _errorHandler, false, 0, true);
    loader.addEventListener(IOErrorEvent.IO_ERROR, _errorHandler, false, 0, true);

    // Load
    try
    {
      loader.load(new URLRequest(this.url));
    }
    catch (e:Dynamic)
    {
      if (this.errorHandler != null) this.errorHandler(e.toString());
      _clean();
      return;
    }
  }
  private function _statusHandler(e:HTTPStatusEvent)
  {
    trace("Status", e.status, this.url);
  }
  private function _errorHandler(e:Event)
  {
    if ( loader != null )
    {
      // TODO: Better error handling...
      if (this.errorHandler != null) this.errorHandler("Error!");
    }

    _clean();
  }
  private function _progressHandler(e:ProgressEvent)
  {
    if ( loader != null )
    {
      var percent:Float = (e.bytesTotal == 0) ? 0 : (e.bytesLoaded / e.bytesTotal);
      this.progress = percent;

      if (this.progressHandler != null) this.progressHandler(percent);
    }
  }
  private function _completeHandler(e:Event)
  {
    if ( loader != null )
    {
      var value:T;

      if ( isJson )
      {
        try
        {
          value = cast(Json.parse(loader.data));
        }
        catch (e:Dynamic)
        {
          if (this.errorHandler != null) this.errorHandler("Error: " + e.toString());
          _clean();
          return;
        }
      }
      else if ( isText )
      {
        value = cast(loader.data);
      }
      else
      {
        var data:ByteArray = loader.data;
        value = cast(Bytes.ofData(data));
      }

      this.progress = 1.0;
      if (this.completeHandler != null) this.completeHandler(value);
    }
    else
    {
      // An error must have occured? Maybe test this case...
      if (this.completeHandler != null) this.completeHandler(null);
    }

    _clean();
  }
  private function _clean()
  {
    if ( loader != null )
    {
      loader.removeEventListener(ProgressEvent.PROGRESS, _progressHandler);
      loader.removeEventListener(Event.COMPLETE, _completeHandler);
      loader.removeEventListener(HTTPStatusEvent.HTTP_STATUS, _statusHandler);
      loader.removeEventListener(ErrorEvent.ERROR, _errorHandler);
      loader.removeEventListener(AsyncErrorEvent.ASYNC_ERROR, _errorHandler);
      loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _errorHandler);
      loader.removeEventListener(IOErrorEvent.IO_ERROR, _errorHandler);

      loader = null;
    }

    clean();
  }
  #elseif js
  private var request:XMLHttpRequest;
  private function _load()
  {
    // TODO: Clean this up a bit using constants for GET, etc...
    request = new XMLHttpRequest();
    request.addEventListener("progress", _progressHandler, false);
    request.onreadystatechange = function(event)
    {
      if (request.readyState != 4) return;

      if (request.status != null && request.status >= 200 && request.status <= 400)
      {
        var value:T;

        if ( isJson )
        {
          try
          {
            if (request.responseType == NONE)
            {
              value = cast(Json.parse(request.responseText));
            }
            else
            {
              value = cast(Json.parse(request.response));
            }
          }
          catch (e:Dynamic)
          {
            if (this.errorHandler != null) this.errorHandler("Error: " + e.toString());
            _clean();
            return;
          }
        }
        else if ( isText )
        {
          if (request.responseType == NONE)
          {
            value = cast(request.responseText);
          }
          else
          {
            value = cast(request.response);
          }
        }
        else
        {
          if (request.responseType == NONE)
          {
            value = cast(Bytes.ofString(request.responseText));
          }
          else
          {
            value = cast(Bytes.ofData(request.response));
          }
        }

        this.progress = 1.0;
        if (this.completeHandler != null) this.completeHandler(value);
      }
      else
      {
        if (this.errorHandler != null) this.errorHandler("Error: " + request.status);
      }

      _clean();
    };

    // Load URL
    try
    {
      request.open("GET", this.url, true);
    }
    catch (e:Dynamic)
    {
      if (this.errorHandler != null) this.errorHandler("Error: " + e.toString());
      _clean();
      return;
    }

    if ( !isText ) request.responseType = ARRAYBUFFER;

    request.send(this.url);
  }
  private function _clean()
  {
    request.removeEventListener("progress", _progressHandler);
    request.onreadystatechange = null;
    request = null;

    clean();
  }
  private function _progressHandler(event)
  {
    if ( request != null )
    {
      var percent:Float = (event.total == 0) ? 0 : (event.loaded / event.total);
      this.progress = percent;

      if (this.progressHandler != null) this.progressHandler(percent);
    }
  }
  #else
  private function _load()
  {
    trace("Not yet supported on this platform...");

    if (this.completeHandler != null) this.completeHandler(null);

    clean();
  }
  #end

  // Clean reference
  public function clean()
  {
    cancel(); // Makes sure to abort connection if there is one

    this.url = null;
    this.completeHandler = null;
    this.errorHandler = null;
    this.progressHandler = null;
  }
}