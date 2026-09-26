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
procedure WaitForTurnCalculationUI;
function IsTurnCalculationRunningUI: Boolean;
procedure CalculateGalaxyTurnAndWait;
procedure QueueGalaxyTurnCalculation;
procedure CalculatePlayerStarTurnAndWait;
procedure QueuePlayerStarTurnCalculation;
procedure QueuePlayerStarPreparation;
implementation
uses
  aPlayerActions;
procedure WaitForTurnCalculationUI;
begin
  WaitForTurnCalculation;
end;
function IsTurnCalculationRunningUI: Boolean;
begin
  Result := IsTurnCalculationRunning;
end;
procedure CalculateGalaxyTurnAndWait;
begin
  StepHumansInHyperspace;
  StartGalaxyTurnCalculation;
  WaitForTurnCalculation;
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
  WaitForTurnCalculation;
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
