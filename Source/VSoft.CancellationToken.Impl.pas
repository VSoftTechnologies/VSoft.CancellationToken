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


unit VSoft.CancellationToken.Impl;

interface

uses
  System.SyncObjs,
  VSoft.CancellationToken;

type
  TCancellationToken = class(TCancellationTokenBase, ICancellationToken, ICancellationTokenManage)
  private
    FEvent : TEvent;
    FIsCancelled : boolean;
  protected
    {$IFDEF MSWINDOWS}
    function  GetHandle: THandle;virtual;
    {$ELSE}
    function GetEvent : TEvent;virtual;
    {$ENDIF}
    function  IsCancelled: boolean;virtual;
    function WaitFor(Timeout: Cardinal): TWaitResult;virtual;
    procedure Cancel;virtual;
    procedure Reset;virtual;
  public
    constructor Create;override;
    destructor Destroy;override;
  end;


implementation

{ TCancellationToken }

procedure TCancellationToken.Cancel;
begin
  FIsCancelled := true;
  FEvent.SetEvent;
end;

constructor TCancellationToken.Create;
begin
  FEvent := TEvent.Create(nil, true, false,'');
  FIsCancelled := false;
end;

destructor TCancellationToken.Destroy;
begin
  FEvent.SetEvent;// in case anything is waiting on this
  FEvent.Free;
  inherited;
end;

{$IFDEF MSWINDOWS}
function TCancellationToken.GetHandle: THandle;
begin
  result := FEvent.Handle;
end;
{$ELSE}
function TCancellationToken.GetEvent : TEvent;
begin
  result := FEvent;
end;
{$ENDIF}

function TCancellationToken.IsCancelled: boolean;
begin
  result := FIsCancelled;
end;

procedure TCancellationToken.Reset;
begin
  FEvent.ResetEvent;
  FIsCancelled := false;

end;


function TCancellationToken.WaitFor(Timeout: Cardinal): TWaitResult;
begin
  result := FEvent.WaitFor(Timeout);
end;

end.
