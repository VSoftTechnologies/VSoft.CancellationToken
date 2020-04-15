unit VSoft.CancellationToken.Tests;

interface

uses
  DUnitX.TestFramework,
  VSoft.CancellationToken;

type
  [TestFixture]
  TCancellationTokenTests = class
  private
    FTokenSource : ICancellationTokenSource;

  public

    [SetupFixture]
    procedure SetupFixture;

    [TeardownFixture]
    procedure TeardownFixture;

    [Test]
    procedure TestCancel;

    [Test]
    procedure TestCancelUsingHandle;

  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  WinApi.Windows;


{ TCancellationTokenTests }

procedure TCancellationTokenTests.SetupFixture;
begin
  FTokenSource := TCancellationTokenSourceFactory.Create;
end;

procedure TCancellationTokenTests.TeardownFixture;
begin
  FTokenSource := nil;
end;

procedure TCancellationTokenTests.TestCancel;
var
  token : ICancellationToken;
  cancelled : boolean;
begin
  FTokenSource.Reset;
  cancelled := false;
  token := FTokenSource.Token;
  TThread.CreateAnonymousThread(
    procedure
    var
      ltoken : ICancellationToken;
    begin
      lToken := token;
      while not lToken.IsCancelled do
      begin
        Sleep(1);
        cancelled := lToken.IsCancelled;
      end;
    end).Start;
//    testThread.Start;
    TThread.Sleep(100);
    FTokenSource.Cancel;
    TThread.Sleep(50);
    Assert.IsTrue(cancelled);
end;


procedure TCancellationTokenTests.TestCancelUsingHandle;
var
  token : ICancellationToken;
  cancelled : boolean;
begin
  FTokenSource.Reset;
  cancelled := false;
  token := FTokenSource.Token;
  TThread.CreateAnonymousThread(
    procedure
    var
      res : integer;
      ltoken : ICancellationToken;
      event : TEvent;
      handles : array[0..1] of THandle;
    begin
      lToken := token;
      event := TEvent.Create(nil,false, false,'');
      handles[0] := lToken.Handle;
      handles[1] := event.Handle;
      try
        while true do
        begin
          res := WaitForMultipleObjects(2, @handles, false, 2000);
          if res = WAIT_OBJECT_0 then
          begin
            //token was cancelled
            cancelled := true;
            exit;
          end;
        end;

      finally
        event.Free;
      end;
    end).Start;
    TThread.Sleep(100);
    FTokenSource.Cancel;
    TThread.Sleep(50);
    Assert.IsTrue(cancelled);
end;

initialization
  TDUnitX.RegisterTestFixture(TCancellationTokenTests);

end.
