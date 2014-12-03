unit ORMCDS;

interface

uses Data.DB,DBClient,mORMot,SynCommons,RTTI,TypInfo,Classes;


(*This is Info record that will be attached to root CDS .Tag and to each nested dataset (array or sub-TSQLRecord list) to
BOTH the TDatasetField.Tag and it's detail TClientdataset.Tag.
*)

type TORMCDSinfo       = class(TObject)
                          public
                           CDS            : TClientdataset; (*Nested TClientdataset*)
                           SQLRecordClass : TSQLRecordClass;(*IF it's SubList (not array), contain type*)
                           RecordTypeInfo : PTypeInfo;       (*IF it';s array (not sublist, contain DynArray PTypeInfo*)

                           DatasetField   : TDatasetField;  (*Master CDS.TDatasetField*)
                           LinkField      : RawUTF8;        (*If it's SubList (not  array), contain link field name that will be =MasterSQLRecord.ID*)

                           {ArrayKeyFields : RawUTF8;
                           ArrayOrdered   : Boolean;}
                           (*Implement array comparing routines to handle key-fields in arrays and ordering
                             for finer-grained 'not touching' array elements when applying updates.
                             At the moment, when SAVEing, all array items are directly compared and overwritten if different from CDS*)

                           function IsArrayLink:Boolean;
                         end;

(*Attempt to create TField descentdants and nested Fields (for arrays) in the CDS*)
procedure ORM_CreateCDSFields(CDS:TClientdataset;AName:RawUTF8;ATypeInfo:PTypeInfo);
(*Add a TSQLRecord sub-class that is linked via DetailSQLrecord.ALinkField=MasterSQLRecord.ID*)
procedure ORM_AddSubField    (CDS:TClientdataset;AFieldName,ALinkField:RawUTF8;AClass:TSQLRecordClass);overload;
(*Add a Dynamic Arrray nested field*)
procedure ORM_AddSubField    (CDS:TClientdataset;AFieldName:RawUTF8;ADynArrayType:PTypeInfo);overload;
procedure ORM_LoadCDSFields  (DB:TSQLRest;CDS:TClientdataset;AName:RawUTF8;AValue:TValue);
function  ORM_SaveCDSFields  (DB:TSQLRest;CDS:TClientdataset;AName:RawUTF8;var AValue:TValue):Integer;

(*Link existing TClientdataset by creating TORMCDSinfo record.*)
procedure ORM_LinkCDS(AParent:TClientDataset;ATypeInfo:PTypeInfo;ALinkField:RawUTF8);
(*Free TORMCDSinfo record info, alternatively free dynamically created TClientdatasets*)
procedure ORM_FreeCDSInfo(CDS:TClientdataset;AFreeCDS:Boolean);

implementation

uses SysUtils,Datasnap.Provider;

procedure ORM_LinkCDS(AParent:TClientDataset;ATypeInfo:PTypeInfo;ALinkField:RawUTF8);
var OInfo : TORMCDSinfo;
    Field : TField;
    I     : Integer;
    Cln   : TClientdataset;
begin
 OInfo:=TORMCDSinfo.Create;
 OInfo.CDS:=AParent;
 case ATypeInfo.Kind of
  tkClass :  begin
              if not GetTypeData(ATypeInfo).ClassType.InheritsFrom(TSQLRecord)
                 then raise Exception.Create('ErrorMessage22');
              OInfo.SQLRecordClass:=TSQLRecordClass(GetTypeData(ATypeInfo).ClassType);
              if AParent.DataSetField<>nil
                 then OInfo.LinkField:=ALinkField;
             end;
  tkDynArray:begin
              if (ATypeInfo^.Kind<>tkDynArray)
                 then raise Exception.Create('ErrorMessage65');
              OInfo.RecordTypeInfo:=ATypeInfo;
             end
 end;

 AParent.Tag:=Integer(OInfo);
 if AParent.DataSetField<>nil
    then begin
          AParent.DataSetField.Tag:=Integer(OInfo);
         end;
end;

procedure ORM_FreeCDSInfo(CDS:TClientdataset;AFreeCDS:Boolean);
var Field : TField;
    OInfo : TORMCDSinfo;
begin
 if (TObject(CDS.Tag) is TORMCDSinfo)
    then (TObject(CDS.Tag) as TORMCDSinfo).Free;
 CDS.Tag:=0;
 for Field in CDS.Fields do
  begin
   if (Field is TDatasetField)
      then begin
            OInfo:=TORMCDSinfo(Field.Tag);
            ORM_FreeCDSInfo(OInfo.CDS,AFreeCDS);
            Field.Tag:=0;
           end;
  end;
 if AFreeCDS
    then CDS.Free;
end;

procedure ORM_CreateCDSFields(CDS:TClientdataset;AName:RawUTF8;ATypeInfo:PTypeInfo);
var Ctx : TRttiContext;
    Typ : TRttiType;
    Fld : TField;
    Cln : TClientDataset;
    I   : Integer;
    S   : String;
    RField:TRttiField;
    RProp :TRttiProperty;
    OInfo :TORMCDSinfo;
begin
 Ctx:=TRttiContext.Create;
 Typ:=Ctx.GetType(ATypeInfo);
 Fld:=CDS.FindField(AName);
 case Typ.TypeKind of
   tkString,
   tkLString    : begin
                   if Fld<>nil
                      then exit;
                   Fld:=TWideStringField.Create(CDS);
                   Fld.Name     :=CDS.Name+AName;
                   Fld.FieldName:=AName;
                   Fld.DataSet:=CDS;
                  end;
   tkInteger    : begin
                   if Fld<>nil
                      then exit;
                   Fld:=TIntegerField.Create(CDS);
                   Fld.Name     :=CDS.Name+AName;
                   Fld.FieldName:=AName;
                   Fld.DataSet:=CDS;
                  end;
   tkEnumeration: begin
                   {???}{Maybe create a lookupfield?}
                   if Fld<>nil
                      then exit;
                   Fld:=TIntegerField.Create(CDS);
                   Fld.Name     :=CDS.Name+AName;
                   Fld.FieldName:=AName;
                   Fld.DataSet:=CDS;
                  end;
   tkSet        : begin
                   case TRttiSetType(typ).ElementType.TypeKind of
                    tkEnumeration : begin
                                     for I := TRttiEnumerationType(TRttiSetType(Typ).ElementType).MinValue to TRttiEnumerationType(TRttiSetType(Typ).ElementType).MaxValue do
                                      begin
                                       S:=GetEnumName(TRttiSetType(Typ).ElementType.Handle,I);
                                       Fld:=CDS.FindField(AName+'_'+S);
                                       if Fld<>nil
                                          then exit;
                                       Fld:=TBooleanField.Create(CDS);
                                       Fld.Name     :=CDS.Name+AName+'_'+S;
                                       Fld.FieldName:=AName+'_'+S;
                                       Fld.DataSet:=CDS;
                                      end;
                                    end
                   else raise Exception.Create('Error Message')
                   end;
                  end;
   tkFloat      : begin
                   if Fld<>nil
                      then exit;
                   Fld:=TFloatField.Create(CDS);
                   Fld.Name     :=CDS.Name+AName;
                   Fld.FieldName:=AName;
                   Fld.DataSet:=CDS;
                  end;
   tkInt64      : begin
                   if Fld<>nil
                      then exit;
                   Fld:=TLargeintField.Create(CDS);
                   Fld.Name     :=CDS.Name+AName;
                   Fld.FieldName:=AName;
                   Fld.DataSet:=CDS;
                  end;
   tkDynArray   : begin
                   ORM_AddSubField    (CDS,AName,TRttiDynamicArrayType(Typ).ElementType.Handle);
                  end;
   tkRecord     : begin
                   for RField in Typ.GetFields do
                    ORM_CreateCDSFields(CDS,RField.Name,RField.FieldType.Handle);
                  end;
   tkClass      : begin
                   if CDS.Tag=0
                      then begin(*Root CDS, create Info*)
                            OInfo:=TORMCDSinfo.Create;
                            OInfo.CDS:=CDS;
                            OInfo.SQLRecordClass:=TSQLRecordClass(TRttiInstanceType(Typ).MetaclassType);
                            CDS.Tag:=Integer(OInfo);
                           end;

                   for RProp in Typ.GetProperties do
                    begin
                     if RProp.IsWritable
                        then ORM_CreateCDSFields(CDS,RProp.Name,RProp.PropertyType.Handle);
                    end;
                  end
  else raise Exception.Create('Error Message');
  end;
 Ctx.Free;
end;

procedure ORM_AddSubField    (CDS:TClientdataset;AFieldName,ALinkField:RawUTF8;AClass:TSQLRecordClass);
var OInfo : TORMCDSinfo;
begin
 OInfo:=TORMCDSinfo.Create;
 OInfo.DatasetField:=TDatasetField.Create(CDS);
 OInfo.DatasetField.Name     :=CDS.Name+AFieldName;
 OInfo.DatasetField.FieldName:=AFieldName;
 OInfo.DatasetField.DataSet  :=CDS;

 OInfo.CDS :=TClientDataset.Create(CDS.Owner);
 OInfo.CDS.Name:=AFieldName;
 OInfo.CDS.DataSetField  :=TDatasetField(OInfo.DatasetField);

 OInfo.LinkField         :=ALinkField;
 OInfo.SQLRecordClass    :=AClass;

 OInfo.DatasetField.Tag:=Integer(OInfo);
 OInfo.CDS         .Tag:=Integer(OInfo);

 ORM_CreateCDSFields(OInfo.CDS,AFieldName,AClass.ClassInfo);
end;

procedure ORM_AddSubField    (CDS:TClientdataset;AFieldName:RawUTF8;ADynArrayType:PTypeInfo);
var OInfo:TORMCDSinfo;
begin
 OInfo:=TORMCDSinfo.Create;
 OInfo.DatasetField:=TDatasetField.Create(CDS);
 OInfo.DatasetField.Name     :=CDS.Name+AFieldName;
 OInfo.DatasetField.FieldName:=AFieldName;
 OInfo.DatasetField.DataSet  :=CDS;

 OInfo.CDS :=TClientDataset.Create(CDS.Owner);
 OInfo.CDS.Name:=AFieldName;
 OInfo.CDS.DataSetField  :=TDatasetField(OInfo.DatasetField);

 OInfo.RecordTypeInfo    :=ADynArrayType;

 ORM_CreateCDSFields(OInfo.CDS,AFieldName,ADynArrayType);

 OInfo.DatasetField.Tag:=Integer(OInfo);
 OInfo.CDS         .Tag:=Integer(OInfo);
end;

procedure ORM_LoadCDSFields(DB:TSQLRest;CDS:TClientdataset;AName:RawUTF8;AValue:TValue);
var Ctx : TRttiContext;
    Typ : TRttiType;
    Fld : TField;
    I   : Integer;
    S   : String;
    RField:TRttiField;
    RProp :TRttiProperty;
    BValue: TValue;
    Obj   : TObject;
    DA    : TDynArray;
    Rec   : TSQLRecord;
    I64   : TID;
    RSTR  : PUTF8Char;
    OInfo : TORMCDSinfo;
begin
 Fld:=CDS.FindField(AName);
{ if Fld=nil
    then exit;}

 Ctx:=TRttiContext.Create;
 Typ:=Ctx.GetType(AValue.TypeInfo);
 case Typ.TypeKind of
   tkString,
   tkLString    : begin
                   Fld.AsString:=AValue.AsString;
                  end;
   tkInteger    : begin
                   Fld.AsInteger:=AValue.AsInteger;
                  end;
   tkEnumeration: begin
                   Fld.AsInteger:=Integer(AValue.GetReferenceToRawData^);
                  end;
   tkSet        : begin
                   case TRttiSetType(typ).ElementType.TypeKind of
                    tkEnumeration : begin
                                     I:=Integer(AValue.GetReferenceToRawData^);
                                     for I := TRttiEnumerationType(TRttiSetType(Typ).ElementType).MinValue to TRttiEnumerationType(TRttiSetType(Typ).ElementType).MaxValue do
                                      begin
                                       S:=GetEnumName(TRttiSetType(Typ).ElementType.Handle,I);
                                       Fld:=CDS.FindField(AName+'_'+S);
                                       if Fld<>nil
                                          then begin
                                                if ((1 shl I) and Integer(AValue.GetReferenceToRawData^))=(1 shl I)
                                                   then Fld.AsBoolean:=True
                                                   else Fld.AsBoolean:=False;
                                               end;
                                      end;
                                    end
                   else raise Exception.Create('Error Message')
                   end;
                  end;
   tkFloat      : begin
                   Fld.AsFloat:=AValue.AsExtended;
                  end;
   tkInt64      : begin
                   Fld.AsLargeInt:=AValue.AsInt64;
                  end;
   tkDynArray   : begin
                   if Fld<>nil
                      then begin
                            {$IFDEF DEBUG}
                            if not (TObject(Fld.Tag) is TORMCDSinfo)
                               then raise Exception.Create('ErrorMessage256');
                            {$ENDIF DEBUG}
                            OInfo:=TORMCDSinfo(Fld.Tag);
                           end;
                   {BValue.Make(nil,TRttiDynamicArrayType(Typ).ElementType.Handle,BValue);}
                   for I := 0 to Pred(AValue.GetArrayLength) do
                    begin
                     BValue:=AValue.GetArrayElement(I);
                     OInfo.CDS.Insert;
                     ORM_LoadCDSFields(DB,OInfo.CDS,'Value',BValue);
{                     Cln.Post;}
                    end;
                  end;
   tkRecord     : begin
                   CDS.Insert;
                   for RField in Typ.GetFields do
                    begin
                     BValue:=RField.GetValue(AValue.GetReferenceToRawData);
                     ORM_LoadCDSFields(DB,CDS,RField.Name,BValue);
                    end;
{                   CDS.Post;}
                  end;
   tkClass      : begin
                   Obj:=AValue.AsObject;
                   CDS.Insert;
                   for I := 0 to Pred(CDS.Fields.Count) do
                    begin
                     if (CDS.Fields[I] is TDataSetField)
                        then begin
                              {$IFDEF DEBUG}
                              if not(TObject(CDS.Fields[I].Tag) is TORMCDSinfo)
                                 then raise Exception.Create('ErrorMessage286');
                              {$ENDIF DEBUG}
                              OInfo:=TORMCDSinfo(CDS.Fields[I].Tag);
                              if OInfo.IsArrayLink
                                 then begin(*Array link*)

                                      end
                                 else begin(*Dataset link*)
                                       RStr:=PUTF8Char(OInfo.LinkField+' = ?');
                                       I64 :=TSQLRecord(Obj).ID;
                                       Rec:=OInfo.SQLRecordClass.CreateAndFillPrepare(DB,RStr,[I64]);
                                       while Rec.FillOne do
                                        begin
                                         ORM_LoadCDSFields(DB,OInfo.CDS,CDS.Fields[I].FieldName,Rec);
                                        end;
                                       Rec.Free;
                                       continue;
                                      end;
                             end;
                     RProp:=Typ.GetProperty(CDS.Fields[I].FieldName);
                     if RProp<>nil
                        then begin
                     (*BValue.Make(nil,RProp.PropertyType.Handle,BValue);*)
                              BValue:=RProp.GetValue(AValue.AsObject);
                              ORM_LoadCDSFields(DB,CDS,RProp.Name,BValue);
                             end;
                    end;
                  end
  else raise Exception.Create('Error Message');
  end;
 Ctx.Free;
end;

function ORM_SaveCDSFields(DB:TSQLRest;CDS:TClientdataset;AName:RawUTF8;var AValue:TValue):Integer;
var Ctx : TRttiContext;
    Typ : TRttiType;
    Fld : TField;
    I,I2: Integer;
    S   : String;
    RField:TRttiField;
    RProp :TRttiProperty;
    BValue: TValue;
    Obj   : TObject;
    DA    : TDynArray;
    Rec   : TSQLRecord;
    I64   : TID;
    RSTR  : PUTF8Char;
    PDS   : TPacketDataSet;
    Changed:Integer;
    OInfo,
    BInfo  : TORMCDSinfo;
    ArrLen : NativeInt;
    P      : Pointer;
    US     : TUpdateStatus;
begin
 Result:=0;
 Fld:=CDS.FindField(AName);
{ if Fld=nil
    then exit;}

 Ctx:=TRttiContext.Create;
 Typ:=Ctx.GetType(AValue.TypeInfo);
 case Typ.TypeKind of
   tkString,
   tkLString    : begin
                   if Fld.OldValue=Fld.NewValue
                      then exit;
                   Inc(Result);
                   AValue:=Fld.AsString;
                  end;
   tkInteger    : begin
                   if Fld.OldValue=Fld.NewValue
                      then exit;
                   Inc(Result);
                   AValue:=Fld.AsInteger;
                  end;
   tkEnumeration: begin
                   if Fld.OldValue=Fld.NewValue
                      then exit;
                   Inc(Result);
                   Integer(AValue.GetReferenceToRawData^):=Fld.AsInteger;
                  end;
   tkSet        : begin
                   I:=Integer(AValue.GetReferenceToRawData^);
                   case TRttiSetType(typ).ElementType.TypeKind of
                    tkEnumeration : begin
                                     I2:=0;
                                     for I := TRttiEnumerationType(TRttiSetType(Typ).ElementType).MinValue to TRttiEnumerationType(TRttiSetType(Typ).ElementType).MaxValue do
                                      begin
                                       S:=GetEnumName(TRttiSetType(Typ).ElementType.Handle,I);
                                       Fld:=CDS.FindField(AName+'_'+S);
                                       if Fld<>nil
                                          then begin
                                                if Fld.AsBoolean
                                                   then I2:=I2 or (1 shl I);
                                               end;
                                      end;
                                     if I2<>Integer(AValue.GetReferenceToRawData^)
                                        then begin
                                              Inc(Result);
                                              Integer(AValue.GetReferenceToRawData^):=I2;
                                             end;
                                    end
                   else raise Exception.Create('Error Message')
                   end;
                  end;
   tkFloat      : begin
                   if Fld.OldValue=Fld.NewValue
                      then exit;
                   Inc(Result);
                   AValue:=Fld.AsFloat;
                  end;
   tkInt64      : begin
                   if Fld.OldValue=Fld.NewValue
                      then exit;
                   Inc(Result);
                   AValue:=Fld.AsLargeInt;
                  end;
   tkDynArray   : begin
                   if Fld=nil
                      then exit;
                   BInfo:=TORMCDSinfo(Fld.Tag);
                   {BValue.Make(nil,TRttiDynamicArrayType(Typ).ElementType.Handle,BValue);}
                   I:=AValue.GetArrayLength;
                   if I<>BInfo.CDS.RecordCount
                      then begin
                            Inc(Result);
                            ArrLen:=BInfo.CDS.RecordCount;
                            P:=PPointer(AValue.GetReferenceToRawData)^;
                            DynArraySetLength(P,Typ.Handle,1,@ArrLEn);
                           end;

                   BInfo.CDS.First;
                   while not BInfo.CDS.Eof do
                    begin
                     US:=BInfo.CDS.UpdateStatus;
                     BValue.From(AValue.GetArrayElement(Pred(BInfo.CDS.RecNo)));
                     BValue:=AValue.GetArrayElement(Pred(BInfo.CDS.RecNo));
                     if ORM_SaveCDSFields(DB,BInfo.CDS,(*Fld.FieldName*)Int32ToUTF8(BInfo.CDS.RecNo),BValue)>0
                        then begin
                              AValue.SetArrayElement(Pred(BInfo.CDS.RecNo),BValue);
                              Inc(Result);
                             end;
                     BInfo.CDS.Next;
                    end;
                  end;
   tkRecord     : begin
                   {$IFDEF DEBUG}
                   if not (TObject(CDS.Tag) is TORMCDSinfo)
                      then raise Exception.Create('ErrorMessage428');
                   {$ENDIF DEBUG}
                   OInfo:=TORMCDSinfo(CDS.Tag);
                   for Fld in CDS.Fields do
                    begin
                     RField:=Typ.GetField(Fld.FieldName);

                     {???}{Set/ENum fields!!!}

                     if RField=nil
                        then continue;
                     BValue:=RField.GetValue(AValue.GetReferenceToRawData);
                     if ORM_SaveCDSFields(DB,OInfo.CDS,Fld.FieldName,BValue)>0
                        then begin
                              Inc(Result);
                              RField.SetValue(AValue.GetReferenceToRawData,BValue);
                             end;
                    end;
                    (*Check special-case SET fields*)
                    for RField in Typ.GetFields do
                     begin
                      case RField.FieldType.TypeKind of
                       tkSet  : begin
                                 BValue.From(RField.GetValue(AValue.GetReferenceToRawData));
                                 BValue:=RField.GetValue(AValue.GetReferenceToRawData);
                                 if ORM_SaveCDSFields(DB,CDS,RField.Name,BValue)>0
                                    then begin
                                          RField.SetValue(AValue.GetReferenceToRawData,BValue);
                                          Inc(Result);
                                         end;
                                end;
                      end;
                     end;

                  end;
   tkClass      : begin
                   {$IFDEF DEBUG}
                   if not (TObject(CDS.Tag) is TORMCDSinfo)
                      then raise Exception.Create('ErrorMessage428');
                   {$ENDIF DEBUG}
                   OInfo:=TORMCDSinfo(CDS.Tag);
                   Rec:=TSQLRecord(AValue.AsObject);
                   (*Update local fields*)
                   for I := 0 to Pred(CDS.Fields.Count) do
                    begin
                     Fld:=CDS.Fields[I];
                     RProp:=Typ.GetProperty(Fld.FieldName);
                     if RProp=nil
                        then continue;
                     BInfo:=TORMCDSinfo(CDS.Fields[I].Tag);
                     if Assigned(BInfo) and not BInfo.IsArrayLink
                        then continue;

                     BValue.Make(nil,RProp.PropertyType.Handle,BValue);
                     BValue:=RProp.GetValue(AValue.AsObject);
                     if ORM_SaveCDSFields(DB,CDS,Fld.FieldName,BValue)>0
                        then begin
                              Changed:=Changed+1;
                              RProp.SetValue(Rec,BValue);
                             end;
                    end;
                   if Changed>0
                      then begin
                            if Rec.ID=0
                               then I64:=DB.Add(Rec,True)
                               else begin
                                     I64:=0;
                                     DB.Update(Rec);
                                    end;
                           end;

                   (*Update SubLists*)
                   for I := 0 to Pred(CDS.Fields.Count) do
                    begin
                     if not(TObject(CDS.Fields[I].Tag) is TORMCDSinfo) or ((TObject(CDS.Fields[I].Tag) as TORMCDSinfo).IsArrayLink)
                        then continue;
                     BInfo:=TORMCDSinfo(CDS.Fields[I].Tag);

                     {$IFDEF DEBUG}
                     if BInfo.LinkField=''
                        then raise Exception.Create('ErrorMessage457');
                     {$ENDIF}

                     BValue.Make(nil,TypeInfo(TSQLRecordClass),BValue);
                     BValue:=BInfo.SQLRecordClass;
                     ORM_SaveCDSFields(DB,BInfo.CDS,CDS.Fields[I].FieldName,BValue);
                     BInfo.CDS.EnableControls;
                    end;
                  end;
   tkClassRef   : begin
                   {$IFDEF DEBUG}
                   if not (TObject(CDS.Tag) is TORMCDSinfo)
                      then raise Exception.Create('ErrorMessage427');
                   {$ENDIF DEBUG}
                   OInfo:=TORMCDSinfo(CDS.Tag);

                   PDS     := TPacketDataSet.Create(nil);
                   PDS.Data:=CDS.Data;
                   PDS.InitAltRecBuffers(True);
                   PDS.Free;

                   CDS.StatusFilter:=[usDeleted];
                   CDS.First;
                   while not CDS.EOF do
                    begin
                     I64:=CDS.FieldByName('ID').AsLargeInt;
                     (*Delete all child records*)
                     for I := 0 to Pred(CDS.Fields.Count) do
                      begin
                       if not(TObject(CDS.Fields[I].Tag) is TORMCDSinfo) or ((TObject(CDS.Fields[I].Tag) as TORMCDSinfo).IsArrayLink)
                          then continue;
                       (*Delete all children tables*)
                       RStr:=PUTF8Char(TORMCDSinfo(CDS.Fields[I].Tag).LinkField+' = ?');
                       DB.Delete(TORMCDSinfo(CDS.Fields[I].Tag).SQLRecordClass,@RStr,[I64]);
                      end;
                     DB.Delete(OInfo.SQLRecordClass,I64);
                     CDS.Next;
                    end;

                   CDS.StatusFilter:=[];
                   Rec:=OInfo.SQLRecordClass.Create;
                   CDS.First;
                   while not CDS.EOF do
                    begin
                     (*Check all fields for changes. Arrays must update as well.*)
                     US:=CDS.UpdateStatus;
                     US:=TClientDataset(TDatasetField(CDS.Fields[2]).Dataset).UpdateStatus;
{                     if (CDS.UpdateStatus=usModified)or(CDS.UpdateStatus=usInserted)
                        then begin}
                              Changed:=0;
                              (*Update all fields+Arrays*)
                              I64:=CDS.FieldByName('ID').AsLargeInt;
                              {$IFDEF DEBUG}
                              if (I64=0)and (CDS.UpdateStatus=usModified)
                                 then raise Exception.Create('ErrorMessage506');
                              {$ENDIF DEBUG}
                              if I64=0
                                 then begin
                                       Rec.ClearProperties;
                                       Changed:=Changed+1;
                                      end
                                 else DB.Retrieve(I64,Rec,True);
                              BValue:=Rec;
                              Changed:=Changed+ORM_SaveCDSFields(DB,CDS,CDS.Fields[I].FieldName,BValue);
                              if I64<>0
                                 then DB.Unlock(Rec);
                            {end;}
                     CDS.Next;
                    end;
                    Rec.Free;
                  end
  else raise Exception.Create('Error Message');
  end;
 Ctx.Free;
end;
{ TORMCDSinfo }

function TORMCDSinfo.IsArrayLink: Boolean;
begin
 Result:=LinkField='';
end;

end.

