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
  TSoundHandler = procedure(const Name: WideString);
  TScreenQueryHandler = function: TGameScreenId;
  TObjectQueryHandler = function: TObject;
  TBooleanQueryHandler = function: Boolean;
  // Questions the simulation asks the UI. Values are part of the command log format.
  TSimQuery = (sqHumanScreen = 0, sqInspectedShip = 1, sqTalkScreenOpen = 2, sqIsFilm = 3);
  // Sees every answer and may replace it: the command log records answers and the replay
  // gives the recorded ones back.
  TQueryAnswerHook = procedure(Query: TSimQuery; var Value: PtrInt);
var
  QueryAnswerHook: TQueryAnswerHook;
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
  // Play a UI sound.
  SoundHandler: TSoundHandler;
  // The screen the human has open. The simulation holds back some actions while the human
  // reads a text quest or watches the star map.
  HumanScreenHandler: TScreenQueryHandler;
  // The ship whose equipment the human is looking at, if any.
  InspectedShipHandler: TObjectQueryHandler;
  // Whether the conversation screen is open.
  TalkScreenOpenHandler: TBooleanQueryHandler;
  // Whether the star map is playing the day's film.
  FilmPlayingHandler: TBooleanQueryHandler;
procedure RequestScreen(Screen: TGameScreenId);
procedure NotifyTurnFailed;
procedure RecordPlayerResult(Victory: Boolean);
procedure ReleasePlayerShip;
procedure NotifyShopStockChanged;
procedure PlaySound(const Name: WideString);
function HumanScreen: TGameScreenId;
function InspectedShip: TObject;
function TalkScreenOpen: Boolean;
function FilmPlaying: Boolean;
implementation

function Answer(Query: TSimQuery; Value: PtrInt): PtrInt;
begin
  if Assigned(QueryAnswerHook) then
    QueryAnswerHook(Query, Value);
  Result := Value;
end;

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

procedure PlaySound(const Name: WideString);
begin
  if Assigned(SoundHandler) then
    SoundHandler(Name);
end;

function HumanScreen: TGameScreenId;
begin
  if Assigned(HumanScreenHandler) then
    Result := HumanScreenHandler
  else
    Result := screenNone;
  Result := TGameScreenId(Answer(sqHumanScreen, Ord(Result)));
end;

function InspectedShip: TObject;
begin
  if Assigned(InspectedShipHandler) then
    Result := InspectedShipHandler
  else
    Result := nil;
  Result := TObject(Answer(sqInspectedShip, PtrInt(Result)));
end;

function TalkScreenOpen: Boolean;
begin
  if Assigned(TalkScreenOpenHandler) then
    Result := TalkScreenOpenHandler
  else
    Result := False;
  Result := Answer(sqTalkScreenOpen, Ord(Result)) <> 0;
end;

function FilmPlaying: Boolean;
begin
  if Assigned(FilmPlayingHandler) then
    Result := FilmPlayingHandler
  else
    Result := False;
  Result := Answer(sqIsFilm, Ord(Result)) <> 0;
end;
end.
