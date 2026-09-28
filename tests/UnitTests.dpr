program UnitTests;
{$MODE delphi}
{$EXCESSPRECISION OFF}
// Asset-free checks of core helpers and file codecs on synthetic input.
// Usage: UnitTests [work directory for temporary files]
uses
{$IFDEF UNIX}
  cthreads,
  cwstring,
{$ENDIF}
  SysUtils,
  Math,
  TestSupport,
  TestRandom,
  TestStrings,
  TestBuffer,
  TestExpression,
  TestCodecs,
  TestCommands,
  TestNet,
  TestPoisonFrees;
var
  WorkDirectory: string;

procedure RunSuite(const Name: string; Suite: TProcedure);
begin
  try
    Suite;
  except
    on E: Exception do
      ReportException(Name, E);
  end;
end;

procedure RunCodecSuite;
begin
  RunCodecTests(WorkDirectory);
end;

begin
  // Match the game: nontrapping IEEE arithmetic and UTF-8 strings.
  SetExceptionMask(
      [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]
  );
  DefaultSystemCodePage := CP_UTF8;
  if ParamCount >= 1 then
    WorkDirectory := ParamStr(1)
  else
    WorkDirectory := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'SpaceRangersUnitTests';
  RunSuite('Random', RunRandomTests);
  RunSuite('Strings', RunStringTests);
  RunSuite('Buffer', RunBufferTests);
  RunSuite('Expression', RunExpressionTests);
  RunSuite('Commands', RunCommandTests);
  RunSuite('Net', RunNetTests);
  RunSuite('PoisonFrees', RunPoisonFreesTests);
  RunSuite('Codecs', RunCodecSuite);
  WriteLn(Format('%d checks, %d failed', [CheckCount, FailureCount]));
  if FailureCount > 0 then
    Halt(1);
end.
