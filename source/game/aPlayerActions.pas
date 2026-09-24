{$EXCESSPRECISION OFF}
unit aPlayerActions;

// CHANGE: ENHANCEMENT - What a human does to the game, as commands (aCommands). The UI calls
// the procedures in the interface; each builds a command and submits it, and the executor
// below does what the UI used to do itself. The executors take the acting ranger from the
// command, never from the screen.
interface
uses
  Types,
  aShip;

// The headless runner and the observer keep the player docked while turns pass.
procedure ParkPlayer;
// Removes the message bubbles that have run out.
procedure PruneMessages;
// Stops the ship and forgets a pending auto-battle target.
procedure OrderStop;
implementation
uses
  SysUtils,
  aCommands,
  aGalaxy,
  aPlanet,
  aPlayer,
  aSession,
  aHuman,
  ThreadCalc,
  Globals;

function Actor(const Command: TPlayerCommand): TPlayer;
begin
  Result := GetPlayer;
end;

procedure ExecuteParkPlayer(const Command: TPlayerCommand);
var
  P: TPlayer;
  I: Integer;
begin
  P := Actor(Command);
  // This is deliberately a sandbox policy: the player stays docked and the
  // observer never writes a save. No landing/travel actions or quests are run.
  if P.InNormalSpace then
  begin
    P.CurrentPlanet := TPlanet(LocalHuman.PlayerStar.Planets[0]);
    P.DockedTo := nil;
  end;
  P.OrderNone(False);
  for I := 1 to P.WeaponCount do
    P.Weapons[I].Target := nil;
  LocalHuman.PlayerAutomaticControl := False;
  LocalHuman.PendingPlayerFollowTarget := nil;
  Session.PlayerStarDayPrepared := False;
end;

procedure ParkPlayer;
begin
  SubmitCommand(NewCommand(ckParkPlayer));
end;

procedure ExecutePruneMessages(const Command: TPlayerCommand);
begin
  PruneExpiredPersistentPlayerMessages;
end;

procedure PruneMessages;
begin
  SubmitCommand(NewCommand(ckPruneMessages));
end;

procedure ExecuteOrderStop(const Command: TPlayerCommand);
begin
  LocalHuman.PendingPlayerFollowTarget := nil;
  Actor(Command).OrderNone(False);
end;

procedure OrderStop;
begin
  SubmitCommand(NewCommand(ckOrderStop));
end;

initialization
  RegisterCommand(ckParkPlayer, @ExecuteParkPlayer);
  RegisterCommand(ckPruneMessages, @ExecutePruneMessages);
  RegisterCommand(ckOrderStop, @ExecuteOrderStop);
end.
