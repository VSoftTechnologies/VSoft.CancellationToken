{***************************************************************************}
{                                                                           }
{           VSoft.CancellationToken - Enables cooperative cancellation      }
{                                     between threads                       }
{                                                                           }
{           Copyright � 2020 Vincent Parrett and contributors               }
{                                                                           }
{           vincent@finalbuilder.com                                        }
{           https://www.finalbuilder.com                                    }
{                                                                           }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Licensed under the Apache License, Version 2.0 (the "License");          }
{  you may not use this file except in compliance with the License.         }
{  You may obtain a copy of the License at                                  }
{                                                                           }
{      http://www.apache.org/licenses/LICENSE-2.0                           }
{                                                                           }
{  Unless required by applicable law or agreed to in writing, software      }
{  distributed under the License is distributed on an "AS IS" BASIS,        }
{  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. }
{  See the License for the specific language governing permissions and      }
{  limitations under the License.                                           }
{                                                                           }
{***************************************************************************}

unit VSoft.CancellationToken;

interface

uses
  System.SyncObjs;

type
  ///  ICancellationToken is passed to async methods
  ///  so that they can determin if the caller has
  ///  cancelled.
  ICancellationToken = interface
  ['{481A7D4C-60D2-4AE5-AE14-F2298E89B638}']
  {$IFDEF MSWINDOWS}
    function  GetHandle: THandle;
  {$ELSE}
    function GetEvent : TEvent;
  {$ENDIF}
    function  IsCancelled: boolean;

  {$IFDEF MSWINDOWS}
    //Note : do not call SetEvent on this handle
    //as it will result in IsSignalled prop
    //returning incorrect results.
    property Handle: THandle read GetHandle;
  {$ELSE}
    property Event : TEvent read GetEvent;
  {$ENDIF}

  end;

  //ICancellationToken implementations must also implement this interface!
  ICancellationTokenManage = interface(ICancellationToken)
  ['{D3472D4F-0155-4DDA-80F8-01F44516952A}']
    procedure Reset;
    procedure Cancel;
  end;

  /// This should be created by calling functions and a reference
  /// stored where it will not go out of scope.
  /// Pass the Token to methods.
  ICancellationTokenSource = interface
  ['{4B7627AE-E8CE-4857-90D7-3C6D5B8A4F9F}']
    procedure Reset;
    procedure Cancel;
    function Token : ICancellationToken;
  end;

  TCancellationTokenBase = class(TInterfacedObject)
  public
    constructor Create;virtual;abstract;
  end;

  TCancellationTokenClass = class of TCancellationTokenBase;

  TCancellationTokenSourceFactory = class
  private
    class var
      FTokenClass : TCancellationTokenClass;
  private
    class constructor Create;
  public
    class procedure RegisterTokenClass(const value : TCancellationTokenClass);
    class function Create : ICancellationTokenSource;
  end;



implementation

uses
  System.SysUtils,
  VSoft.CancellationToken.Impl;

type
  TCancellationTokenSource = class(TInterfacedObject, ICancellationTokenSource )
  private
    FToken : ICancellationTokenManage;
  protected
    procedure Reset;
    procedure Cancel;
    function Token : ICancellationToken;
  public
    constructor Create(const token : ICancellationTokenManage);
  end;


{ TCancellationTokenSourceFactory }

class function TCancellationTokenSourceFactory.Create: ICancellationTokenSource;
var
  token : IInterface;
  theToken : ICancellationTokenManage;
begin
  token := TCancellationTokenSourceFactory.FTokenClass.Create as ICancellationTokenManage;
  if not Supports(token, ICancellationToken) then
    raise Exception.Create('Registered Token class does not implement required interface ICancellationToken');
  if not Supports(token, ICancellationTokenManage,theToken) then
    raise Exception.Create('Registered Token class does not implement required interface ICancellationTokenManage');
  result := TCancellationTokenSource.Create(theToken);
end;

class constructor TCancellationTokenSourceFactory.Create;
begin
  TCancellationTokenSourceFactory.FTokenClass := TCancellationToken;
end;

class procedure TCancellationTokenSourceFactory.RegisterTokenClass(const value: TCancellationTokenClass);
begin
  TCancellationTokenSourceFactory.FTokenClass := value;
end;

{ TCancellationTokenSource }

procedure TCancellationTokenSource.Cancel;
begin
  FToken.Cancel;
end;

constructor TCancellationTokenSource.Create(const token: ICancellationTokenManage);
begin
  FToken := token;
end;

procedure TCancellationTokenSource.Reset;
begin
  FToken.Reset;
end;

function TCancellationTokenSource.Token: ICancellationToken;
begin
  result := FToken;
end;


end.
