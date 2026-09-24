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
  aGalaxy;

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
  InterlockedIncrement(TurnYieldedToUi);
  try
    while ((CurrentScreenId = screenJump) or (CurrentScreenId = screenArcadeBattle))
        and (Galaxy.ScoreScreenDismissed = 0) do
      SysUtils.Sleep(1);
  finally
    InterlockedDecrement(TurnYieldedToUi);
  end;
end;

procedure RefreshShopGoods;
begin
  EquipmentShopScreen.ClearGoodsControls;
  EquipmentShopScreen.BuildGoodsControls;
  EquipmentShopScreen.UpdateScrollButtons;
end;

procedure InstallSimEventHandlers;
begin
  ScreenRequestHandler := SwitchScreen;
  TurnFailedHandler := LeaveScreenLoop;
  PlayerResultHandler := RecordScore;
  PlayerShipReleaseHandler := WaitForPlayerShipScreens;
  ShopStockChangedHandler := RefreshShopGoods;
end;
end.
