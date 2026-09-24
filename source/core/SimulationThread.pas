{$EXCESSPRECISION OFF}
unit SimulationThread;

// CHANGE: ENHANCEMENT - Debug check that simulation state changes only on the turn thread
// while a turn job runs. The UI thread may change it between jobs, and while the turn
// thread waits for it (a dialogue or the score screen). Builds with assertions (-Sa, the
// debug configuration) log the first violation at each site with a backtrace; the check
// compiles to nothing otherwise.
interface
threadvar
  InTurnJob: Boolean;
var
  TurnJobRunning: Boolean;
  // Counts the turn thread's waits for the UI; the UI may change state during them.
  TurnYieldedToUi: Integer;
  // Violations seen, for tests.
  SimulationThreadViolations: Integer;
procedure CheckSimulationThread(const Site: AnsiString);
implementation
uses
  SysUtils,
  Classes,
  GR_Main;

var
  ReportedSites: TStringList;

procedure ReportViolation(const Site: AnsiString);
var
  Frame, Caller: Pointer;
  Depth: Integer;
  Text: AnsiString;
begin
  InterlockedIncrement(SimulationThreadViolations);
  if ReportedSites = nil then
    ReportedSites := TStringList.Create;
  if ReportedSites.IndexOf(Site) >= 0 then
    Exit;
  ReportedSites.Add(Site);
  Text := 'Simulation state changed outside the turn thread during a turn: ' + Site;
  Frame := get_frame;
  for Depth := 1 to 12 do
  begin
    Caller := get_caller_addr(Frame);
    if Caller = nil then
      Break;
    Text := Text + LineEnding + BackTraceStrFunc(Caller);
    Frame := get_caller_frame(Frame);
    if Frame = nil then
      Break;
  end;
  // The unit tests have no session log; drop the I/O error it leaves.
  try
    AppendLogLineThreadSafe(Text);
  except
  end;
  IOResult;
end;

procedure CheckSimulationThread(const Site: AnsiString);
begin
  {$IFOPT C+}
  if TurnJobRunning and not InTurnJob and (TurnYieldedToUi = 0) then
    ReportViolation(Site);
  {$ENDIF}
end;

finalization
  ReportedSites.Free;
end.
