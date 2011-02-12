package
{
	import com.adobe.serialization.json.JSONDecoder;
	import com.brightcove.api.APIModules;
	import com.brightcove.api.BrightcoveModuleWrapper;
	import com.brightcove.api.CustomModule;
	import com.brightcove.api.dtos.MediaDTO;
	import com.brightcove.api.events.*;
	import com.brightcove.api.modules.AdvertisingModule;
	import com.brightcove.api.modules.ContentModule;
	import com.brightcove.api.modules.ExperienceModule;
	import com.brightcove.api.modules.VideoPlayerModule;
	
	import flash.display.*;
	import flash.events.*;
	import flash.external.*;
	import flash.geom.Rectangle;
	import flash.net.*;
	import flash.text.*;
	import flash.utils.*;
	
	public class SocialVibePlugin extends CustomModule	
	{
		[Embed(source="assets/powered_by_sv.png")]
		public static var LogoClass:Class;
		
		[Embed(source="assets/loading.png")]
		public static var LoadingClass:Class;
		
		[Embed(source="assets/choice_panel.png")]
		public static var PanelBackgroundClass:Class;
		
		[Embed(source="assets/start_btn.png")]
		public static var StartButtonClass:Class;
		
		[Embed(source="assets/chose_warning.png")]
		public static var WarningClass:Class;
		
		static private const SV_ACTIVITIES_READY:String = 'svActivitiesReady';
		
		private var _player:BrightcoveModuleWrapper;
		private var _experienceModule:ExperienceModule;
		private var _adModule:AdvertisingModule;
		private var _videoPlayerModule:VideoPlayerModule;
		private var _contentModule:ContentModule;
		
		private var _media:MediaDTO;
		private var _adPolicy:Object;
		
		private var _cookie:SharedObject;
		private var _network_user_id:String;
		private var _parnter_config_hash:String;
		private var _availableActivities:Array;
		
		private var _loading:Bitmap;
		private var _warning:Bitmap;
		private var _svUnit:Sprite;
		
		private var _activityId:Number;
		private var _checkIntervalId:uint;
		
		public function SocialVibePlugin()
		{
			
		}
		
		override public function setInterface(player:IEventDispatcher):void
		{
			_player = new BrightcoveModuleWrapper(player);
			_adModule = _player.getModule(APIModules.ADVERTISING) as AdvertisingModule;
			_experienceModule = _player.getModule(APIModules.EXPERIENCE) as ExperienceModule;
			
			if (_adModule)
				disableAds();
			
			if (_experienceModule)
				_experienceModule.addEventListener(ExperienceEvent.TEMPLATE_READY, onTemplateReady);
		}
		
		private function disableAds():void
		{
			_adPolicy = _adModule.getAdPolicy();
			
			var newAdPolicy:Object = _adModule.getAdPolicy();
			//_adModule.enableExternalAds(false);
			//_adModule.enableOverrideAds(false);
			
			var blockAdPolicy:Object = new Object();
			blockAdPolicy.adPlayCap = 0;
			blockAdPolicy.playAdOnLoad = false;
			blockAdPolicy.prerollAds = false;
			blockAdPolicy.midrollAds = false;
			blockAdPolicy.postrollAds = false;
			_adModule.setAdPolicy(blockAdPolicy);
		}
		
		private function showLoading():void
		{
			_loading = new LoadingClass() as Bitmap;
			_loading.x = (_videoPlayerModule.getDisplayWidth() - _loading.width)/2;
			_loading.y = (_videoPlayerModule.getDisplayHeight() - _loading.height)/2;
			_experienceModule.getStage().addChild(_loading);
		}
		
		private function onTemplateReady(event:ExperienceEvent):void
		{ 
			_experienceModule.removeEventListener(ExperienceEvent.TEMPLATE_READY, onTemplateReady);
			
			initialize(); 
		}
		
		override protected function initialize():void
		{
			_videoPlayerModule = _player.getModule(APIModules.VIDEO_PLAYER) as VideoPlayerModule;
			_contentModule = _player.getModule(APIModules.CONTENT) as ContentModule;
			
			_videoPlayerModule.addEventListener(MediaEvent.BEGIN, onMediaBegin);
			_videoPlayerModule.addEventListener(MediaEvent.PLAY, onMediaPlay);
			
			
			
			_videoPlayerModule.setEnabled(false);
			
			var args:Array = LoaderInfo(_experienceModule.getStage().root.loaderInfo).url.split('pch=');
			
			if (args.length > 0)
				_parnter_config_hash = args[1];
			_experienceModule.debug('partner_config_hash:' + _parnter_config_hash);
			
			/*
			var cookie:SharedObject = SharedObject.getLocal('sv1', "/");
			if (cookie && cookie.data['nuid'])
			{
			_network_user_id = cookie.data['nuid'] as String;
			}
			else
			{
			_network_user_id = GUID.create();
			if (cookie)
			{
			cookie.data['nuid'] = _network_user_id;
			cookie.flush();
			}
			}
			*/
			_network_user_id = String(Math.round(Math.random()*1000000));
			
			var onLoad:Function = function(e:Event):void {
				_availableActivities = new JSONDecoder(e.currentTarget.data, false).getValue();
				dispatchEvent(new Event(SV_ACTIVITIES_READY));
			};
			loadActivities(onLoad);
		}
		
		private function loadActivities(onLoad:Function):void
		{
			var availableActivities:URLLoader = new URLLoader();
			availableActivities.addEventListener(IOErrorEvent.IO_ERROR, function(e:Event):void { });
			availableActivities.addEventListener(Event.COMPLETE, onLoad);
			
			availableActivities.load(new URLRequest("http://qa.partners.socialvi.be/" + _parnter_config_hash + "/activities/available.json?max_activities=1&network_user_id=" + _network_user_id));
		}
		
		private function onMediaPlay(event:MediaEvent):void {
			_media = event.media;
		}
		
		private function onMediaBegin(event:MediaEvent):void {
			_videoPlayerModule.removeEventListener(MediaEvent.BEGIN, onMediaBegin);
			
			_videoPlayerModule.pause(true);
			
			if (_availableActivities == null)
			{
				showLoading();
				
				addEventListener(SV_ACTIVITIES_READY, beginSocialVibe, false, 0, true);
			}
			else
			{
				beginSocialVibe();
			}
		}
		
		private function beginSocialVibe(event:Event = null):void
		{
			if (_availableActivities == null) return;
			
			if (_loading && _experienceModule.getStage().contains(_loading))
				_experienceModule.getStage().removeChild(_loading);
			
			if (_availableActivities.length == 0)
			{
				_experienceModule.debug('playing video');
				_videoPlayerModule.setEnabled(true);
				_videoPlayerModule.play();
			}
			else
			{
				var activity:Object = _availableActivities[0];
				_activityId = Number(activity.id);
				
				// show ad option screen
				var stage:Stage = _experienceModule.getStage();
				
				_svUnit = new Sprite();
				_svUnit.x = _videoPlayerModule.getX();
				_svUnit.y = _videoPlayerModule.getY();
				stage.addChild(_svUnit);
				
				var g:Graphics = _svUnit.graphics;
				g.beginFill(0x000000, 0.9);
				g.drawRect(0, 0, _videoPlayerModule.getDisplayWidth(), _videoPlayerModule.getDisplayHeight());
				
				var panel:Sprite = new Sprite();
				panel.addChild(new PanelBackgroundClass());
				panel.scaleX = panel.scaleY = Math.min(1, Math.min(_videoPlayerModule.getDisplayWidth()/panel.width, _videoPlayerModule.getDisplayHeight()/panel.height));
				panel.x = (_videoPlayerModule.getDisplayWidth() - panel.width)/2;
				panel.y = (_videoPlayerModule.getDisplayHeight() - panel.height)/2;
				_svUnit.addChild(panel);
				
				var brandIcon:SVImage = new SVImage(activity.image_url);
				brandIcon.scaleImage(42, 42);
				brandIcon.roundCorners(2);
				brandIcon.x = 318;
				brandIcon.y = 105;
				panel.addChild(brandIcon);
				
				var option1:SVRadioButton = new SVRadioButton(new Rectangle(0, 0, 325, 40));
				option1.x = 40;
				option1.y = 105;
				panel.addChild(option1);
				
				var option2:SVRadioButton = new SVRadioButton(new Rectangle(0, 0, 370, 22));
				option2.x = option1.x;
				option2.y = option1.y + 60;
				panel.addChild(option2);
				
				option1.addEventListener(SVRadioButton.SELECTED, function(e:Event):void {
					_warning.visible = false;
					option2.unselect();
				});
				option2.addEventListener(SVRadioButton.SELECTED, function(e:Event):void {
					_warning.visible = false;
					option1.unselect();
				});
				
				_warning = new WarningClass();
				_warning.x = (panel.width - _warning.width)/2;
				_warning.y = 250;
				panel.addChild(_warning);
				_warning.visible = false;
				
				var btn:SVButton = new SVButton(new StartButtonClass() as Bitmap);
				btn.addEventListener(MouseEvent.CLICK, function(e:Event):void {
					if (option1.isSelected())
					{
						sizedPopup(activity.activity_window_url, activity.activity_window_width, activity.activity_window_height);
					}
					else if (option2.isSelected())
					{
						_svUnit.visible = false;
						_adModule.setAdPolicy(_adPolicy);
						_videoPlayerModule.setEnabled(true);
						_videoPlayerModule.play();
					}
					else
					{
						_warning.visible = true;
					}
				});
				btn.x = (panel.width - btn.width)/2;
				btn.y = 212;
				panel.addChild(btn);
				
				var logo:Bitmap = new LogoClass() as Bitmap;
				logo.x = _videoPlayerModule.getDisplayWidth() - logo.width;
				logo.y = _videoPlayerModule.getDisplayHeight() - logo.height;
				_svUnit.addChild(logo);
			}
		}
		
		private function sizedPopup(url:String, width:String, height:String):void
		{
			if(!ExternalInterface.available || ExternalInterface.call("function() { this.svWindow = window.open('" + url + "','','width=" + width + ",height=" + height + ",scrollbars=1,status=0,toolbar=0,menubar=0,location=0'); return (!this.svWindow); }"))
			{
				_videoPlayerModule.setEnabled(true);
				_videoPlayerModule.play();
			}
			else
			{
				_checkIntervalId = setInterval(checkPopup, 500);
			}
		}
		
		private function checkPopup():void
		{
			if (ExternalInterface.call("function() { return (this.svWindow.closed); }") == true)
			{
				clearInterval(_checkIntervalId);
				
				if (_svUnit && _experienceModule.getStage().contains(_svUnit))
					_experienceModule.getStage().removeChild(_svUnit);
				
				showLoading();
				
				// verifying completion
				var onLoad:Function = function(e:Event):void {
					_availableActivities = new JSONDecoder(e.currentTarget.data, false).getValue();
					
					if (_loading && _experienceModule.getStage().contains(_loading))
						_experienceModule.getStage().removeChild(_loading);
					
					if (_availableActivities == null || _availableActivities.length == 0 || _availableActivities[0].id != _activityId)
					{
						// turn off ads
						_media.economics = 0;
						_contentModule.updateMedia(_media);
					}
					else
					{
						// re-enable ads
						_adModule.setAdPolicy(_adPolicy);
					}
					
					_videoPlayerModule.setEnabled(true);
					_videoPlayerModule.play();
				};
				loadActivities(onLoad);
				
			}
		}
	}
	
}


import flash.display.*;
import flash.events.*;
import flash.geom.*;
import flash.net.*;
import flash.system.*;

internal class SVButton extends Sprite
{
	static public const IMAGE_LOADED:String = 'buttonImageLoaded';
	
	protected var _buttonImage:Bitmap;
	protected var _rollover:Bitmap;
	
	public function SVButton(b:Bitmap)
	{
		_buttonImage = b;
		
		loadImage();
	}
	
	protected function onRollOver(e:MouseEvent):void
	{
		if (_rollover)
			_rollover.visible = true;
	}
	
	protected function onRollOut(e:MouseEvent):void
	{
		if (_rollover)
			_rollover.visible = false;
	}
	
	protected function loadImage():void
	{
		if (!this.hasEventListener(MouseEvent.ROLL_OVER))
		{
			this.buttonMode = this.useHandCursor = true;
			this.addEventListener(MouseEvent.ROLL_OVER, onRollOver);
			this.addEventListener(MouseEvent.ROLL_OUT, onRollOut);
		}
		
		_buttonImage.smoothing = true;
		
		addChildAt(_buttonImage, 0);
		
		if (_rollover)
			removeChild(_rollover);
		
		_rollover = new Bitmap(_buttonImage.bitmapData.clone());
		_rollover.alpha = 0.5;
		_rollover.blendMode = BlendMode.MULTIPLY;
		_rollover.visible = false;
		addChild(_rollover);
		
		dispatchEvent(new Event( IMAGE_LOADED ));
	}
}

internal class SVRadioButton extends Sprite
{
	[Embed(source="assets/radio_selected.png")]
	public static var SelectedClass:Class;
	
	[Embed(source="assets/radio_unselected.png")]
	public static var UnselectedClass:Class;
	
	public static const SELECTED:String     	= 'selected';
	public static const UNSELECTED:String     = 'unselected';
	
	protected var _selected:Boolean;
	
	public function SVRadioButton(hitarea:Rectangle)
	{
		graphics.beginFill(0, 0);
		graphics.drawRect(hitarea.x, hitarea.y, hitarea.width, hitarea.height);
		
		addChild(new SelectedClass());
		addChild(new UnselectedClass());
		
		buttonMode = useHandCursor = true;
		addEventListener(MouseEvent.CLICK, onClick, false, 0, true);
	}
	
	private function onClick(e:MouseEvent):void
	{
		if (!_selected)
		{
			select();
		}
	}
	
	public function select():void
	{
		if (!_selected)
		{
			swapChildrenAt(0, 1);
			_selected = true;
			
			dispatchEvent(new Event( SELECTED ));
		}
	}
	
	public function unselect():void
	{
		if (_selected)
		{
			swapChildrenAt(0, 1);
			_selected = false;
			
			dispatchEvent(new Event( UNSELECTED ));
		}
	}
	
	public function isSelected():Boolean
	{
		return _selected;
	}
}

class SVImage extends Sprite
{
	public static const IMAGE_LOADED:String = "imageLoaded";
	
	protected var _width:Number;
	protected var _height:Number;
	protected var _origWidth:Number;
	protected var _origHeight:Number;
	
	protected var _url:String;
	protected var _img:DisplayObject;
	protected var _imgLoader:Loader;
	
	protected var _imageMask:Sprite;
	protected var _curveSize:Number;
	
	public function SVImage(url:String = "")
	{
		_curveSize = 0;
		
		if (url)
		{
			imageURL = url;
		}
	}
	
	public function set imageURL(url:String):void
	{
		_url = url;
		
		if (_url)
		{
			_imgLoader = new Loader();
			_imgLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, imgLoadErr, false, 0, true);
			_imgLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, imgLoaded, false, 0, true);
			_imgLoader.load(new URLRequest(_url), new LoaderContext(true));
		}
	}
	
	protected function imgLoaded(e:Event):void
	{
		_imgLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, imgLoadErr);
		_imgLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE, imgLoaded);
		
		try {
			var img:Bitmap = Bitmap(_imgLoader.content);
			img.smoothing = true;
			addImage(img);
		} catch (err:Error) {
			addImage(_imgLoader); // loading an img outside the security sandbox
		}
	}
	
	protected function addImage(img:DisplayObject):void
	{
		_img = img;
		addChild(_img);
		
		_width = _origWidth = _img.width;
		_height = _origHeight = _img.height;
		
		dispatchEvent(new Event( IMAGE_LOADED ));
	}
	
	protected function imgLoadErr(e:IOErrorEvent):void
	{
		_imgLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, imgLoadErr);
		_imgLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE, imgLoaded);
	}
	
	public function scaleImage(w:Number, h:Number):void
	{
		if (_img == null)
		{
			addEventListener(IMAGE_LOADED, function(e:Event):void {
				removeEventListener(IMAGE_LOADED, arguments.callee);
				scaleImage(w, h);
			});
			return;
		}
		
		if (!isNaN(w))
		{
			_width = w;
			_img.scaleX = (_width/_origWidth);
		}
		
		if (!isNaN(h))
		{
			_height = h;
			_img.scaleY = (_height/_origHeight);
		}
	}
	
	public function roundCorners(size:Number):void
	{
		if (_img == null)
		{
			addEventListener(IMAGE_LOADED, function(e:Event):void {
				removeEventListener(IMAGE_LOADED, arguments.callee);
				roundCorners(size);
			});
			return;
		}
		
		_curveSize = size;
		
		if (_imageMask && contains(_imageMask)) {
			removeChild(_imageMask);
		}
		_imageMask = new Sprite();
		_imageMask.graphics.beginFill(0, 1);
		_imageMask.graphics.drawRoundRect(0, 0, width, height, _curveSize);
		addChild(_imageMask);
		mask = _imageMask;
	}
}

