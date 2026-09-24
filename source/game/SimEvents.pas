{$EXCESSPRECISION OFF}
unit SimEvents;

// CHANGE: CLEANUP - Calls from the simulation to whatever presents it. Simulation units call
// these instead of screen units; the UI installs the handlers at startup
// (SimEventHandlers). A handler left nil does nothing, which is what a runner without a UI
// wants. Handlers run on the thread that raises the event, often the turn thread.
interface
uses
  GlobalsV;
type
  TScreenRequestHandler = procedure(Screen: TGameScreenId);
  TPlayerResultHandler = procedure(Victory: Boolean);
  TSimEventHandler = procedure;
var
  // Close the current screen and open Screen next.
  ScreenRequestHandler: TScreenRequestHandler;
  // A turn job failed; leave the screen loop.
  TurnFailedHandler: TSimEventHandler;
  // The player's game ended; record it in the score table.
  PlayerResultHandler: TPlayerResultHandler;
  // The player's ship is about to be freed. The UI may hold the turn until no screen
  // still shows it.
  PlayerShipReleaseHandler: TSimEventHandler;
  // The equipment shop's stock changed while the player had it open.
  ShopStockChangedHandler: TSimEventHandler;
procedure RequestScreen(Screen: TGameScreenId);
procedure NotifyTurnFailed;
procedure RecordPlayerResult(Victory: Boolean);
procedure ReleasePlayerShip;
procedure NotifyShopStockChanged;
implementation

procedure RequestScreen(Screen: TGameScreenId);
begin
  if Assigned(ScreenRequestHandler) then
    ScreenRequestHandler(Screen);
end;

procedure NotifyTurnFailed;
begin
  if Assigned(TurnFailedHandler) then
    TurnFailedHandler;
end;

procedure RecordPlayerResult(Victory: Boolean);
begin
  if Assigned(PlayerResultHandler) then
    PlayerResultHandler(Victory);
end;

procedure ReleasePlayerShip;
begin
  if Assigned(PlayerShipReleaseHandler) then
    PlayerShipReleaseHandler;
end;

procedure NotifyShopStockChanged;
begin
  if Assigned(ShopStockChangedHandler) then
    ShopStockChangedHandler;
end;
end.
