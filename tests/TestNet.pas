unit TestNet;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunNetTests;
implementation
uses
  SysUtils,
  EC_Buf,
  NetTransport,
  NetDelta,
  TestSupport;

// A state-like buffer: repetitive records with varying fields.
procedure FillState(Buffer: TBufEC; Count, Seed: Integer; InsertAt: Integer = -1);
var
  I: Integer;
begin
  Buffer.Clear;
  RandSeed := Seed;
  for I := 0 to Count - 1 do
  begin
    Buffer.AddInt32(I);
    Buffer.AddInt32(Random(1000));
    Buffer.AddWideStringZ('Ship' + IntToStr(I mod 97));
    Buffer.AddDouble(I * 0.5);
    if I = InsertAt then
      Buffer.AddWideStringZ('inserted');
  end;
end;

function SameBytes(Left, Right: TBufEC): Boolean;
begin
  Result := (Left.DataSize = Right.DataSize)
      and ((Left.DataSize = 0) or CompareMem(Left.Data, Right.Data, Left.DataSize));
end;

procedure RunDeltaTests;
var
  Old, New, Compressed, Whole, Restored: TBufEC;
  I: Integer;
begin
  Old := TBufEC.Create;
  New := TBufEC.Create;
  Compressed := TBufEC.Create;
  Whole := TBufEC.Create;
  Restored := TBufEC.Create;
  try
    FillState(Old, 100000, 1);
    // A few changed fields, and an inserted record that shifts everything after it.
    FillState(New, 100000, 1, 50000);
    for I := 0 to 20 do
      New.SetInt32At(I * 20000 + 4, 424242);
    CompressState(New, nil, Whole);
    ExpandState(Whole.Data, Whole.DataSize, nil, Restored);
    Check(SameBytes(New, Restored), 'a whole state expands to itself');
    CompressState(New, Old, Compressed);
    ExpandState(Compressed.Data, Compressed.DataSize, Old, Restored);
    Check(SameBytes(New, Restored), 'a delta expands to the new state');
    Check(Compressed.DataSize * 20 < Whole.DataSize, 'a delta of a few changes is small');
    Restored.Clear;
    try
      ExpandState(Compressed.Data, Compressed.DataSize, nil, Restored);
      Check(False, 'a delta without its reference is refused');
    except
      on E: Exception do
        Check(True, 'a delta without its reference is refused');
    end;
  finally
    Old.Free;
    New.Free;
    Compressed.Free;
    Whole.Free;
    Restored.Free;
  end;
end;

procedure RunTransportTests;
var
  Listener: TNetListener;
  Client, Server: TNetConnection;
  Payload, Big: TBufEC;
  Kind: TNetMessageKind;
  Deadline: QWord;
  Received: Integer;
  Kinds: array[0..2] of Integer;
  BigSame: Boolean;
begin
  Listener := TNetListener.Create(0);
  Client := nil;
  Server := nil;
  Payload := TBufEC.Create;
  Big := TBufEC.Create;
  try
    Check(Listener.Port > 0, 'the listener picks a port');
    Client := TNetConnection.Connect('127.0.0.1', Listener.Port, 5000);
    Check(Client <> nil, 'a client connects to the listener');
    if Client = nil then
      Exit;
    Deadline := GetTickCount64 + 5000;
    while (Server = nil) and (GetTickCount64 < Deadline) do
    begin
      Server := Listener.Accept;
      if Server = nil then
        Sleep(1);
    end;
    Check(Server <> nil, 'the listener accepts the client');
    if Server = nil then
      Exit;
    FillState(Big, 300000, 7);
    Payload.AddWideStringZ('hello');
    Client.Send(1, Payload);
    Client.Send(2, nil, 0);
    Client.Send(3, Big);
    Received := 0;
    BigSame := False;
    Deadline := GetTickCount64 + 10000;
    while (Received < 3) and (GetTickCount64 < Deadline) do
    begin
      Client.Poll;
      Server.Wait(10);
      while Server.Receive(Kind, Payload) do
      begin
        Kinds[Received] := Kind;
        if Kind = 1 then
          CheckText('hello', Payload.ReadWideString, 'a message keeps its payload');
        if Kind = 2 then
          CheckInt(0, Payload.DataSize, 'an empty message stays empty');
        if Kind = 3 then
          BigSame := SameBytes(Big, Payload);
        Inc(Received);
      end;
    end;
    CheckInt(3, Received, 'every message arrives');
    Check((Kinds[0] = 1) and (Kinds[1] = 2) and (Kinds[2] = 3), 'messages arrive in order');
    Check(BigSame, 'a large message arrives whole');
    Check(Client.BytesSent = Server.BytesReceived, 'byte counts agree');
    Client.Close;
    Deadline := GetTickCount64 + 5000;
    while not Server.Closed and (GetTickCount64 < Deadline) do
      Server.Wait(10);
    Check(Server.Closed, 'a closed peer closes the connection');
    Check(TNetConnection.Connect('127.0.0.1', 1, 500) = nil, 'connecting to a closed port fails');
  finally
    Client.Free;
    Server.Free;
    Listener.Free;
    Payload.Free;
    Big.Free;
  end;
end;

procedure RunNetTests;
begin
  RunDeltaTests;
  RunTransportTests;
end;

end.
