unit TestRandom;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunRandomTests;
implementation
uses
  SysUtils,
  aGalaxy,
  aMyFunction,
  CPDiapClass,
  SimulationThread,
  TestSupport;
const
  // AdvanceRandomSeed maps these seeds to themselves, so they take its fallback step.
  AdvanceFixedPointA = 3180859188;
  AdvanceFixedPointB = 4187862156;

procedure CheckAdvanceSequence(Seed: Cardinal; const Expected: array of Cardinal);
var
  i: Integer;
  Returned: Cardinal;
begin
  for i := 0 to High(Expected) do
  begin
    Returned := AdvanceRandomSeed(Seed);
    CheckHex(Expected[i], Seed, Format('AdvanceRandomSeed step %d', [i]));
    CheckHex(Seed, Returned, Format('AdvanceRandomSeed result %d', [i]));
  end;
end;

procedure CheckNextIntSequence(BoundA: Integer; BoundB: Integer; const Expected: array of Integer);
var
  i: Integer;
  Seed: Cardinal;
begin
  Seed := 12345;
  for i := 0 to High(Expected) do
    CheckInt(
        Expected[i],
        NextRandomIntRange(BoundA, BoundB, Seed),
        Format('NextRandomIntRange(%d, %d) #%d', [BoundA, BoundB, i])
    );
  CheckHex(711474624, Seed, Format('NextRandomIntRange(%d, %d) final seed', [BoundA, BoundB]));
end;

procedure CheckTextQuestRandom;
var
  i: Integer;
  First: array[0..9] of Int64;
  Value: Double;
begin
  TextQuestRandomState := 42;
  for i := 0 to High(First) do
  begin
    First[i] := TextQuestRandom(7);
    Check((First[i] >= 0) and (First[i] < 7), Format('TextQuestRandom(7) #%d in range', [i]));
  end;
  TextQuestRandomState := 42;
  for i := 0 to High(First) do
    CheckInt(First[i], TextQuestRandom(7), Format('TextQuestRandom(7) #%d repeats', [i]));
  CheckInt(0, TextQuestRandom(0), 'TextQuestRandom(0)');
  CheckInt(0, TextQuestRandom(-5), 'TextQuestRandom(-5)');
  Check(TextQuestRandom(Int64(1) shl 40) < Int64(1) shl 40, 'TextQuestRandom(2^40) in range');
  for i := 1 to 100 do
  begin
    Value := TextQuestRandom;
    Check((Value >= 0) and (Value < 1), 'TextQuestRandom float in [0, 1)');
  end;
end;

// The check is compiled only with assertions (debug builds and these tests).
procedure CheckSimulationThreadCheck;
var
  Before: Integer;
begin
  {$IFOPT C+}
  Before := SimulationThreadViolations;
  CheckSimulationThread('test idle');
  CheckInt(Before, SimulationThreadViolations, 'no turn running');
  TurnJobRunning := True;
  try
    InTurnJob := True;
    CheckSimulationThread('test turn thread');
    InTurnJob := False;
    CheckInt(Before, SimulationThreadViolations, 'turn thread during a turn');
    Inc(TurnYieldedToUi);
    CheckSimulationThread('test yielded');
    Dec(TurnYieldedToUi);
    CheckInt(Before, SimulationThreadViolations, 'turn waiting for the UI');
    CheckSimulationThread('test violation');
    CheckInt(Before + 1, SimulationThreadViolations, 'other thread during a turn');
  finally
    TurnJobRunning := False;
    InTurnJob := False;
  end;
  {$ENDIF}
end;

procedure RunRandomTests;
begin
  CheckTextQuestRandom;
  CheckSimulationThreadCheck;
  // Chaotic-random mode reads the galaxy; without one every helper is deterministic.
  Check(Galaxy = nil, 'Galaxy is nil for RNG tests');

  CheckHex(567, StepRandomSeed(0), 'StepRandomSeed(0)');
  CheckHex(8548, StepRandomSeed(1), 'StepRandomSeed(1)');
  CheckHex(4294959882, StepRandomSeed($FFFFFFFF), 'StepRandomSeed($FFFFFFFF)');
  CheckHex(2147484215, StepRandomSeed($80000000), 'StepRandomSeed($80000000)');

  CheckAdvanceSequence(1, [8548, 68222156, 3315156855, 1268732343, 2515072347]);
  CheckAdvanceSequence($FFFFFFFF, [530735, 4235796668, 206151794, 325019943, 4118926886]);
  CheckAdvanceSequence(
      AdvanceFixedPointA,
      [1372531267, 2005609668, 3722867277, 3915418338, 3067168337]
  );
  CheckAdvanceSequence(
      AdvanceFixedPointB,
      [1852107235, 2685609630, 1963987057, 2245285462, 1019995205]
  );

  CheckNextIntSequence(-5, 5, [-2, 5, 1, -2, 2, -2]);
  CheckNextIntSequence(10, 3, [8, 4, 7, 7, 8, 3]);
  CheckNextIntSequence(7, 7, [7, 7, 7, 7, 7, 7]);
  CheckNextIntSequence(0, 99, [13, 97, 20, 60, 57, 24]);

  CheckInt(1, SeededRandomIntRange(1, 6, 0), 'SeededRandomIntRange(1, 6, 0)');
  CheckInt(6, SeededRandomIntRange(1, 6, 5), 'SeededRandomIntRange(1, 6, 5)');
  CheckInt(1, SeededRandomIntRange(1, 6, 6), 'SeededRandomIntRange(1, 6, 6)');
  CheckInt(4, SeededRandomIntRange(1, 6, $FFFFFFFF), 'SeededRandomIntRange(1, 6, $FFFFFFFF)');
  CheckInt(-17, SeededRandomIntRange(-10, -20, $FFFFFFFF), 'SeededRandomIntRange reversed');
  CheckInt(
      -2147483647,
      SeededRandomIntRange(-2147483647, 2147483647, $FFFFFFFF),
      'SeededRandomIntRange full span'
  );
end;

end.
