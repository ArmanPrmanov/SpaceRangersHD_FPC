unit TestStrings;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunStringTests;
implementation
uses
  EC_Str,
  GR_Main,
  TestSupport;

procedure RunDelimiterTests;
begin
  CheckInt(0, CountDelimitedPartsW('', ','), 'CountDelimitedPartsW empty');
  CheckInt(1, CountDelimitedPartsW('abc', ','), 'CountDelimitedPartsW no delimiter');
  CheckInt(4, CountDelimitedPartsW('a,b;c,', ',;'), 'CountDelimitedPartsW two delimiters');
  CheckText('b', ExtractDelimitedPartW('a,b;c', 1, ',;'), 'ExtractDelimitedPartW middle');
  CheckText('c', ExtractDelimitedPartW('a,b;c', 2, ',;'), 'ExtractDelimitedPartW last');
  CheckText('b,c', ExtractDelimitedRangeW('a,b,c,d', 1, 2, ','), 'ExtractDelimitedRangeW');
  CheckText(' // note', ExtractLineCommentW('x=1 // note'), 'ExtractLineCommentW');
  CheckText('x=1', RemoveLineCommentW('x=1   // note'), 'RemoveLineCommentW');
end;

procedure RunNumberTests;
begin
  Check(IsIntegerTextW('-120'), 'IsIntegerTextW signed');
  Check(not IsIntegerTextW('12a'), 'IsIntegerTextW letter');
  Check(not IsIntegerTextW(''), 'IsIntegerTextW empty');
  CheckInt(1203, ExtractDigitsToIntW('a1b2c03'), 'ExtractDigitsToIntW');
  CheckInt(-45, ExtractSignedDigitsToIntW('x-4y5'), 'ExtractSignedDigitsToIntW');
  CheckFloat(-12.25, ParseDecimalToSingleW('-12.25'), 1e-6, 'ParseDecimalToSingleW dot');
  CheckFloat(3.5, ParseDecimalToSingleW('3,5'), 1e-6, 'ParseDecimalToSingleW comma');
  CheckText('2.5', FloatToWideString(2.5), 'FloatToWideString');
  CheckText('0', IntToWideString(0), 'IntToWideString zero');
  CheckText('-2147483647', IntToWideString(-2147483647), 'IntToWideString negative');
  // Abs(Low(Integer)) stays negative; the port keeps the legacy output.
  CheckText('-0', IntToWideString(Low(Integer)), 'IntToWideString Low(Integer)');
  CheckText('0', CardinalToHexWideString(0), 'CardinalToHexWideString zero');
  CheckText('deadbeef', CardinalToHexWideString($DEADBEEF), 'CardinalToHexWideString');
  CheckText('0042', IntToFixedWidthWideString(42, 4), 'IntToFixedWidthWideString pad');
  CheckText('12', IntToFixedWidthWideString(12345, 2), 'IntToFixedWidthWideString cut');
  CheckText('True', BoolToWideString(True), 'BoolToWideString');
end;

// The game loads its case table from language data; supply a small one.
procedure SetCaseTable(const Lower: WideString; const Upper: WideString);
var
  i: Integer;
begin
  SetLength(WideCaseTable, Length(Lower));
  for i := 1 to Length(Lower) do
  begin
    WideCaseTable[i - 1].LowerChar := Lower[i];
    WideCaseTable[i - 1].UpperChar := Upper[i];
  end;
end;

procedure RunTextTests;
var
  List: TStringsEC;
begin
  CheckText('a b', TrimWideString(#9' a b '#13#10#0), 'TrimWideString');
  CheckText('', TrimWideString('  '), 'TrimWideString blank');
  SetCaseTable('abжё', 'ABЖЁ');
  CheckText('AB, Жc', UpperCaseWideString('ab, жc'), 'UpperCaseWideString');
  CheckText('ёж ab', LowerCaseWideString('ЁЖ AB'), 'LowerCaseWideString');
  WideCaseTable := nil;
  CheckText('ab', UpperCaseWideString('ab'), 'UpperCaseWideString without table');
  CheckText('xYYxYY', ReplaceAllWideString('xaxa', 'a', 'YY'), 'ReplaceAllWideString grow');
  CheckText('aa', ReplaceAllWideString('aaa', 'aa', 'a'), 'ReplaceAllWideString overlap');
  CheckText('bcb', RemoveWideStringChars('abcab', 'a'#0), 'RemoveWideStringChars');
  // '<<' drops one '<'; the tag that follows is still removed.
  CheckText('Hi  x', RemoveTextTagsW('<clr>Hi <<you></clr> x'), 'RemoveTextTagsW');
  CheckText('a < b', RemoveTextTagsW('a < b'), 'RemoveTextTagsW unterminated');
  // Closing tags do not match the opening pattern.
  CheckText(
      'a<b>c</clr>',
      RemoveMatchingTextTagsW('a<b><CLR>c</clr>', 'clr', 'CLR'),
      'RemoveMatchingTextTagsW'
  );
  CheckInt(3, FindTextOffsetW('abcabc', 'ab', 1), 'FindTextOffsetW start');
  CheckInt(-1, FindTextOffsetW('abc', 'x'), 'FindTextOffsetW missing');
  CheckInt(3, FindTextPosW('c', 'abc'), 'FindTextPosW');
  CheckText(
      'file.name',
      ExtractFileNameNoExtW('C:\dir/sub\file.name.txt'),
      'ExtractFileNameNoExtW'
  );
  CheckText('txt', ExtractFileExtNoDotW('dir/file.name.txt'), 'ExtractFileExtNoDotW');
  CheckText('C:\dir/sub', ExtractFileDirW('C:\dir/sub\file.txt'), 'ExtractFileDirW');
  CheckText('S a v e ', EncodeLegacySaveLabel('Save'), 'EncodeLegacySaveLabel');
  CheckText(
      'Сейв',
      DecodeLegacySaveLabel(EncodeLegacySaveLabel('Сейв')),
      'Legacy label round trip'
  );
  CheckText(
      'Shhuka Yozh',
      TransliterateCyrillicToLatin('Щука Ёж'),
      'TransliterateCyrillicToLatin'
  );

  List := TStringsEC.Create;
  try
    List.Add('one');
    List.Add('two');
    List.Add('three');
    CheckInt(3, List.GetCount, 'TStringsEC count');
    CheckInt(1, List.IndexOf('two'), 'TStringsEC IndexOf');
    List.Delete(0);
    CheckText('three', List.GetTextAt(1), 'TStringsEC delete');
  finally
    List.Free;
  end;
end;

procedure RunStringTests;
begin
  RunDelimiterTests;
  RunNumberTests;
  RunTextTests;
end;

end.
