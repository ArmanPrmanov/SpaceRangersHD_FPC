{$EXCESSPRECISION OFF}
unit aCalc;
{$R-}
{$Q-}
{$B-}
{$A8}
interface
uses
  ThreadCalc;
var
  TurnCalculationPhase: TTurnCalculationPhase;
  // CHANGE: ENHANCEMENT - Called on the UI thread while it waits for a job, so that a networked
  // game keeps taking messages (ROADMAP.md, Phase 5; docs/network.md, Threads). Nil without a
  // network session.
  TurnWaitPumpHook: procedure;
procedure WaitForTurnCalculationUI;
function IsTurnCalculationRunningUI: Boolean;
procedure CalculateGalaxyTurnAndWait;
procedure QueueGalaxyTurnCalculation;
procedure CalculatePlayerStarTurnAndWait;
procedure QueuePlayerStarTurnCalculation;
procedure QueuePlayerStarPreparation;
implementation
uses
  aPlayerActions,
  aSession;
const
  // How often a wait with TurnWaitPumpHook set calls it.
  TurnWaitPumpMs = 10;
procedure WaitForTurnCalculationUI;
begin
  // CHANGE: FIX - On the turn thread (a remote human's talk answer) the job is the caller.
  if (Session.TurnCalculationThread <> nil) and Session.TurnCalculationThread.IsCurrentThread then
    Exit;
  if not Assigned(TurnWaitPumpHook) then
  begin
    WaitForTurnCalculation;
    Exit;
  end;
  while IsTurnCalculationRunning do
    if not Session.TurnCalculationThread.WaitForIdle(TurnWaitPumpMs) then
      TurnWaitPumpHook;
end;
function IsTurnCalculationRunningUI: Boolean;
begin
  Result := IsTurnCalculationRunning;
end;
procedure CalculateGalaxyTurnAndWait;
begin
  StepHumansInHyperspace;
  StartGalaxyTurnCalculation;
  WaitForTurnCalculationUI;
end;
// CHANGE: ENHANCEMENT - The hyperspace steps of the humans whose jump screen is not shown run
// before the galaxy job, as the jump screen runs the local human's (hot-seat, ROADMAP.md,
// Phase 4). Only in multiplayer.
procedure QueueGalaxyTurnCalculation;
begin
  StepHumansInHyperspace;
  StartGalaxyTurnCalculation;
end;
procedure CalculatePlayerStarTurnAndWait;
begin
  StartPlayerStarTurnCalculation;
  WaitForTurnCalculationUI;
end;
procedure QueuePlayerStarTurnCalculation;
begin
  StartPlayerStarTurnCalculation;
end;
procedure QueuePlayerStarPreparation;
begin
  StartPlayerStarPreparation;
end;
end.
