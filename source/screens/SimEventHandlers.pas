{$EXCESSPRECISION OFF}
unit SimEventHandlers;

// CHANGE: CLEANUP - The UI's handlers for the simulation's events (SimEvents). The bodies
// are the code the simulation used to run itself.
interface
procedure InstallSimEventHandlers;
implementation
uses
  SysUtils,
  SimEvents,
  SimulationThread,
  GI_MessageLoop,
  GR_Main,
  Globals,
  GlobalsV,
  aGalaxy,
  aHuman,
  fStarMap;

procedure SwitchScreen(Screen: TGameScreenId);
begin
  RequestedScreenId := Screen;
  TMessageLoopGI(RegisteredScreens[Ord(CurrentScreenId)]).RequestClose(1);
end;

procedure LeaveScreenLoop;
begin
  RequestedScreenId := screenNone;
  TMessageLoopGI(RegisteredScreens[Ord(CurrentScreenId)]).RequestClose(1);
  ExitScreenLoop := True;
end;

procedure RecordScore(Victory: Boolean);
begin
  ScoreScreen.RecordPlayerResult(Victory);
end;

// The jump screen and the arcade battle still show the player's ship. Each sets
// Galaxy.ScoreScreenDismissed once it no longer needs it.
procedure WaitForPlayerShipScreens;
begin
  // CHANGE: ENHANCEMENT - The UI shows the score screen while the turn thread waits.
  BeginTurnWaitForUi(False);
  try
    while ((CurrentScreenId = screenJump) or (CurrentScreenId = screenArcadeBattle))
        and (Galaxy.ScoreScreenDismissed = 0) do
      SysUtils.Sleep(1);
  finally
    EndTurnWaitForUi(False);
  end;
end;

procedure RefreshShopGoods;
begin
  EquipmentShopScreen.ClearGoodsControls;
  EquipmentShopScreen.BuildGoodsControls;
  EquipmentShopScreen.UpdateScrollButtons;
end;

procedure PlayUiSound(const Name: WideString);
begin
  SoundManager.PlaySound(Name);
end;

function OpenScreen: TGameScreenId;
begin
  Result := CurrentScreenId;
end;

function ShipOnOpenScreen: TObject;
begin
  Result := nil;
  if GetInnermostScreenLoop = HangarScreen then
    Result := HangarScreen.SelectedShip
  else if GetInnermostScreenLoop = ScannerScreen then
    Result := ScannerScreen.ShipToInspect
  else if GetInnermostScreenLoop = ShipScreen then
    Result := LocalHuman.PlayerHoldShip;
end;

function IsTalkScreenOpen: Boolean;
begin
  Result := (TalkScreen <> nil) and (TalkScreen.ParentLoop <> nil);
end;

function IsFilmPlaying: Boolean;
begin
  Result := StarMapScreen.Mode = smmTurnFilm;
end;

procedure InstallSimEventHandlers;
begin
  ScreenRequestHandler := SwitchScreen;
  TurnFailedHandler := LeaveScreenLoop;
  PlayerResultHandler := RecordScore;
  PlayerShipReleaseHandler := WaitForPlayerShipScreens;
  ShopStockChangedHandler := RefreshShopGoods;
  SoundHandler := PlayUiSound;
  HumanScreenHandler := OpenScreen;
  InspectedShipHandler := ShipOnOpenScreen;
  TalkScreenOpenHandler := IsTalkScreenOpen;
  FilmPlayingHandler := IsFilmPlaying;
end;
end.
