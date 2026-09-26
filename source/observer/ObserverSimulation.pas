{$EXCESSPRECISION OFF}
unit ObserverSimulation;
interface
uses
  Classes,
  ObserverCapture;
type
  TObserverWorker = class(TThread)
    Recording: TObserverRecording;
    Failure: string;
    CaptureEnabled: Boolean;
    procedure Execute; override;
  end;
var
  ObserverSimulatedTurns: Integer;
procedure ParkObserverPlayer;
procedure SimulateParkedTurn;
implementation
uses
  aPlayerActions,
  aSession,
  aHuman,
  SysUtils,
  Math,
  Globals,
  GlobalsV,
  aGalaxy,
  aShip,
  aPlayer,
  aPlanet,
  aRanger,
  ThreadCalc,
  ObserverHooks,
  WorkerErrors;
// CHANGE: ENHANCEMENT - Park the player while the observer advances the simulation.
procedure ParkObserverPlayer;
var
  P: TPlayer;
begin
  P := LocalPlayer;
  if (P = nil) or (LocalHuman.PlayerStar = nil) then
    raise Exception.Create('Observer requires a campaign save with a player.');
  if Galaxy.StasisModEnabled = 1 then
    raise Exception.Create('Disable stasis before starting observer mode.');
  if P.InHyperspace then
    raise Exception.Create('Load a save made in a system or on a planet for observer mode.');
  if P.InNormalSpace and (LocalHuman.PlayerStar.Planets.Count = 0) then
    raise Exception.Create('Observer needs a planet in the starting system to park the player.');
  ParkPlayer;
  // The observer never writes a save.
  TurnSaveStep := 0;
end;

// CHANGE: ENHANCEMENT - Share one parked turn between the observer and the headless runner.
procedure SimulateParkedTurn;
begin
  PruneMessages;
  // Parked player: same two ordinary jobs as the docked turn controller.
  OrderStop;
  StartPlayerStarTurnCalculation;
  WaitForTurnCalculation;
  RaisePendingWorkerError;
  if LocalPlayer = nil then
    raise Exception.Create('The player no longer exists.');
  StartGalaxyTurnCalculation;
  WaitForTurnCalculation;
  RaisePendingWorkerError;
end;

procedure TObserverWorker.Execute;
begin
  try
    SetExceptionMask(
        [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]
    );
    SetRoundMode(rmNearest);
    if CaptureEnabled then
    begin
      Recording := TObserverRecording.Create;
      ObserverWriting := Recording;
      ObserverStep := CaptureObserverStep;
      ObserverHit := CaptureObserverHit;
    end;
    try
      SimulateParkedTurn;
      if Recording <> nil then
        Recording.CaptureTransits(False);
      Inc(ObserverSimulatedTurns);
    finally
      ObserverStep := nil;
      ObserverHit := nil;
      ObserverWriting := nil;
    end;
  except
    on E: Exception do
      Failure := E.ClassName + ': ' + E.Message
  end;
end;

end.
