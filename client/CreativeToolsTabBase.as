// Copyright 2011 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS-IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
package {
	import commands.CommandEvent;
	import commands.CommandMgr;
	
	import containers.ActivatableModuleLoaderBase;
	import containers.PaletteWindow;
	
	import controls.CreativeToolsResizingThumbToggleButtonBar;
	
	import creativeTools.ICreativeTool;
	import creativeTools.NestedControlsCanvasBase;
	
	import events.*;
	
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.events.Event;
	import flash.events.MouseEvent;
	
	import mx.containers.Canvas;
	import mx.containers.ViewStack;
	import mx.controls.Button;
	import mx.controls.Text;
	import mx.core.Application;
	import mx.core.UIComponent;
	import mx.events.CloseEvent;
	import mx.events.FlexEvent;
	import mx.events.IndexChangedEvent;
	
	import util.FontManager;
	import util.ITabContainer;
	import util.ModulePreloader;
	import util.ShapeManager;
	
	public class CreativeToolsTabBase extends Canvas implements IActivatable, IActionListener, ITabContainer {
		// MXML-defined variables
		[Bindable] public var _cvsTemplate:Canvas;
		[Bindable] public var _btnUndo:Button;
		[Bindable] public var _btnRedo:Button;
		[Bindable] public var _btnSave:Button;
		[Bindable] public var _btnOptions:Button;
		[Bindable] public var _vstk:ViewStack;
		[Bindable] public var _pwndInfo:PaletteWindow;
		[Bindable] public var _txtHelp:Text;
		[Bindable] public var hasDocument:Boolean;
		
		private var _fActive:Boolean;
		private var _zmv:ZoomView;
		private var _crtlActive:ICreativeTool = null;
		[Bindable] protected var _urs:UndoRedoSave;
		[Bindable] public var _tbbarOpen:CreativeToolsResizingThumbToggleButtonBar;
		
		private var _fIndexChangeListening:Boolean = false;

		//
		// Initialization (not including state restoration)
		//
		
		public function CreativeToolsTabBase() {
			super();
			addEventListener(FlexEvent.INITIALIZE, OnInitialize);
		}
		
		public function LoadTab(strTab:String): void {
			if (!strTab || !_vstk || !_tbbarOpen) return;
			var astrParts:Array = strTab.split(':',2);
			if (astrParts.length > 1) {
				strTab = astrParts[0];
			}
			var dobChild:DisplayObject = _vstk.getChildByName(strTab);
			if (!dobChild) return;
			var childIndex:int = _vstk.getChildIndex(dobChild);
			_tbbarOpen.selectedIndex = childIndex;
			_vstk.selectedIndex = childIndex;

			if (astrParts.length > 1) {
				// Now select the child

				// This is for deep linking. For example, if you load
				// http://local.mywebsite.com/app#/create/featured Picnik loads, then loads the Create
				// module, then (once that is loaded) selects the Featured sub-tab
				// TODO(bsharon): verify this works as intended for dynamically loaded sub-tabs.
				if (dobChild is ITabContainer)
					(dobChild as ITabContainer).LoadTab(astrParts[1]);
			}
		}
		
		public function PerformActionIfSafe(act:IAction): void {
			if (_crtlActive != null) {
				_crtlActive.PerformActionIfSafe(act);
			} else {
				act.Do();
			}
		}

		public function PerformAction(act:IAction): void {
			if (_crtlActive != null) {
				_crtlActive.PerformAction(act);
			} else {
				act.Do();
			}
		}

		// Only track ViewStack index changes while the container is active. This keeps
		// us from doing a lot of behind the scenes BS when application state is being
		// restored and both the In and Out bridge container's ViewStack indices are
		// being set.
		private function OnShow(): void {
			_vstk.addEventListener(IndexChangedEvent.CHANGE, OnViewStackIndexChange);
			_fIndexChangeListening = true;
			addEventListener(HelpEvent.SHOW_HELP, OnShowHelp, true);
			addEventListener(HelpEvent.HIDE_HELP, OnHideHelp, true);
			addEventListener(HelpEvent.SET_HELP_TEXT, OnSetHelpText, true);
			_pwndInfo.visible = false;
			_pwndInfo.addEventListener(CloseEvent.CLOSE, OnPwndInfoClose);
		}
		
		private function OnHide(): void {
			removeEventListener(HelpEvent.SHOW_HELP, OnShowHelp, true);
			removeEventListener(HelpEvent.HIDE_HELP, OnHideHelp, true);
			removeEventListener(HelpEvent.SET_HELP_TEXT, OnSetHelpText, true);
			_pwndInfo.removeEventListener(CloseEvent.CLOSE, OnPwndInfoClose);
			_vstk.removeEventListener(IndexChangedEvent.CHANGE, OnViewStackIndexChange);
			_fIndexChangeListening = false;
		}
		
		private function OnPwndInfoClose(evt:Event): void {
			_pwndInfo.visible = false;
			PicnikBase.SetPersistentClientState("CreativeTools.Effects.InfoVisible", false);
			if (_crtlActive) _crtlActive.HelpStateChange(false);
		}
		
		protected function OnShowHelp(evt:HelpEvent): void {
			OnSetHelpText(evt);
			_pwndInfo.parent.removeChild(_pwndInfo);
			Application.application.addChild(_pwndInfo);
			_pwndInfo.visible = true;
		}
		
		protected function OnHideHelp(evt:HelpEvent): void {
			_pwndInfo.visible = false;
		}
		
		private function OnOptionsClick(evt:MouseEvent): void {
			var mnu:EditCreateOptions = new EditCreateOptions();
			mnu.actionListener = this;
			mnu.Show(this, _btnOptions);
		}
		
		protected function OnSetHelpText(evt:HelpEvent): void {
			if (evt.helpText != null) _txtHelp.htmlText = evt.helpText;
			if (evt.helpTitle != null) _pwndInfo.title = evt.helpTitle;
		}
		
		private function FindChildrenWithPropertyValue(vstk:ViewStack, strPropName:String, obValue:Object): Array {
			return _FindChildrenByPropertyValue(vstk, strPropName, obValue, true);
		}
		
		private function FindChildrenWithoutPropertyValue(vstk:ViewStack, strPropName:String, obValue:Object): Array {
			return _FindChildrenByPropertyValue(vstk, strPropName, obValue, false);
		}
		
		private function _FindChildrenByPropertyValue(vstk:ViewStack, strPropName:String, obValue:Object, fMatch:Boolean): Array {
			var adobChildren:Array = [];
			for (var i:Number = 0; i < vstk.numChildren; i++) {
				var dobChild:DisplayObject = vstk.getChildAt(i);
				if (fMatch == (strPropName in dobChild && dobChild[strPropName] == obValue))
					adobChildren.push(dobChild);
			}
			return adobChildren;
		}
		
		public function OnInitialize(evt:Event): void {
			removeEventListener(FlexEvent.INITIALIZE, OnInitialize);
			_urs = new UndoRedoSave(_btnUndo, _btnRedo, _btnSave);
			_btnOptions.addEventListener(MouseEvent.CLICK, OnOptionsClick);

			currentState = PicnikBase.app.applicationState;
			
			var aobChildrenToRemove:Array;
			// Google plus
			if (PicnikBase.app._pas.googlePlusUI) {
				aobChildrenToRemove = FindChildrenWithoutPropertyValue(_vstk, "googlePlus", true);
			} else {
				aobChildrenToRemove = FindChildrenWithPropertyValue(_vstk, "googlePlusExclusive", true);
				if (!(AccountMgr.GetInstance().perms & Permissions.Admin)) {
					aobChildrenToRemove.push(_vstk.getChildByName("_ctAdmin"));
				}
			}

			for each (var dobChild:DisplayObject in aobChildrenToRemove) {
				_vstk.removeChild(dobChild);
			}

			// go out and get Font and Shape definitions from the server, process
			// them, but don't build their graphical representations.  This shuffles
			// a bit of work around so when the user clicks on the font/shape tabs,
			// there's less lag time as they're displayed.
			FontManager.GetFontList(
				function(afntf:Array, afntc:Object):void {	// font families, categories
					// NOP
				}
			);
		}
		
		//
		// IActivatable implementation
		//

		// When the bridge container is activated, activate its selected child		
		public function OnActivate(strCmd:String=null): void {
			Debug.Assert(!_fActive, "CreativeToolsTabBase.OnActivate already active!");
			_fActive = true;
			OnShow();
			
			// Show the master view but apply the template view's style to it
			_zmv = PicnikBase.app.AttachZoomView(this, _cvsTemplate);
			_zmv.imageView.FilterSelection(ImageView.kFreeSelection);
			_zmv.imageView.ReparentObjectPalette(Application.application as DisplayObjectContainer);
			
			// Hook up undo/redo/save to the current ImageDocument
			_urs.Activate();
			CommandMgr.AddEventListener("GenericDocument.Undo", CommandEvent.BEFORE_EXECUTE, OnUrsButton);

			// At load time it is possible to be shown without receiving an
			// FlexEvent.SHOW. This is a problem for us because that's when
			// we add the _vstk IndexChangedEvent.CHANGE listener. OnActivate
			// IS called at load time so we recover from this situation here.
			if (!_fIndexChangeListening) {
				_vstk.addEventListener(IndexChangedEvent.CHANGE, OnViewStackIndexChange);
				_fIndexChangeListening = true;
			}
			ActivateCreativeToolAtIndex(_vstk.selectedIndex);
			PicnikBase.app.addEventListener(ActiveDocumentEvent.CHANGE, OnActiveDocumentChange);
			OnActiveDocumentChange(new ActiveDocumentEvent(ActiveDocumentEvent.CHANGE, null,
					PicnikBase.app.activeDocument));
			
			// When this tab becomes active, start loading ModCreate in the background. No-op if it's
			// already loaded.
			ModulePreloader.Instance.AddModule(PicnikBase.app.GetLocModuleName('ModCreate'), int.MAX_VALUE - 1);
			ModulePreloader.Instance.AddModule(PicnikBase.app.GetLocModuleName('ModDialog'), int.MAX_VALUE);
			ModulePreloader.Instance.Start();
		}
		
		// When the bridge container is deactivated, deactivate its selected child		
		public function OnDeactivate(): void {
			_fActive = false;
			OnHide();
			
			PicnikBase.app.removeEventListener(ActiveDocumentEvent.CHANGE, OnActiveDocumentChange);
			PicnikBase.app.DetachZoomView(this);
			_zmv.imageView.ReparentObjectPalette(_zmv);
			_zmv = null;
			
			if (_crtlActive != null) {
				_crtlActive.OnDeactivate(null);
				_crtlActive = null;
			}
			CommandMgr.RemoveEventListener("GenericDocument.Undo", CommandEvent.BEFORE_EXECUTE, OnUrsButton);
			_urs.Deactivate();

			if (_pwndInfo) _pwndInfo.visible = false; // Make sure we hide the help window
		}

		private function OnActiveDocumentChange(evt:ActiveDocumentEvent): void {
			hasDocument = PicnikBase.app.activeDocument != null;
		}
		
		public function get active(): Boolean {
			return _fActive;
		}
		
		private function OnUrsButton(evt:CommandEvent): void {
			_crtlActive = _vstk.selectedChild as ICreativeTool;
			if (_crtlActive) {
				if (_crtlActive.Deselect()) {
					evt.preventDefault(); // Cancel the event and deselect our effect
				}
			}
		}

		private function OnViewStackIndexChange(evt:IndexChangedEvent): void {
			ActivateCreativeToolAtIndex(evt.newIndex);
		}
		
		private function ActivateCreativeToolAtIndex(index:int) : void {
			var child:DisplayObject = _vstk.getChildAt(index);
			if (child is ICreativeTool) {
				SetActiveTool(child as ICreativeTool);
			} else if (child is ActivatableModuleLoaderBase) {
				var moduleLoader:ActivatableModuleLoaderBase = child as ActivatableModuleLoaderBase;
				if (!moduleLoader.creativeTool) {
					moduleLoader.OnActivate();
					moduleLoader.addEventListener(ActivatableModuleLoaderBase.READY, function(evt:Event) : void {
						SetActiveTool(moduleLoader.creativeTool);
					});
				} else {
					SetActiveTool(moduleLoader.creativeTool);
				}
			}
		}
		
		private function SetActiveTool(nextCreativeTool:ICreativeTool) : void {
			if (_crtlActive != null) {
				_crtlActive.OnDeactivate(nextCreativeTool);
			}
			var prevCreativeTool:ICreativeTool = _crtlActive;
			_crtlActive = nextCreativeTool;
			if (!nextCreativeTool.active) {
				_crtlActive.OnActivate(prevCreativeTool);
			}
			if (_crtlActive is NestedControlsCanvasBase) {
				var nestedControlsCanvasBase:NestedControlsCanvasBase = NestedControlsCanvasBase(_crtlActive);
				if (!nestedControlsCanvasBase.undoRedoSave) {
					nestedControlsCanvasBase.undoRedoSave = this._urs;
				}
			}
			var strOld:String = prevCreativeTool ? UIComponent(prevCreativeTool).id : "<none>";
			var strNew:String = nextCreativeTool ? UIComponent(nextCreativeTool).id : "<none>";
			PicnikService.Log("changed from subtab " + strOld + " to subtab " + strNew);
		}
	}
}


