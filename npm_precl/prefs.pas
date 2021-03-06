unit prefs;

{$H+}
interface
uses
  inifiles, define_types,SysUtils,classes,turbolesion;

function DoLesion (var lPrefs: TLDMPrefs): boolean;
procedure SetDefaultPrefs (var lPrefs: TLDMPrefs);
procedure ReadParamStr;

implementation

uses nifti_img, hdr,nifti_hdr, valformat,StatThdsUtil,filename,npmform;

procedure MsgX(lStr: string);
begin
   MainForm.NPMmsg(lStr);
end;

procedure ClearMsgX;
begin
   MainForm.NPMmsgClear
end;

procedure SetDefaultPrefs (var lPrefs: TLDMPrefs);
begin
  //lPrefs.unusedbool := true;
  lPrefs.tTest := true;
  lPrefs.BMtest := false;
  lPrefs.Ltest := false;
  lPrefs.nPermute := 0;
  lPrefs.CritPct := -1;//use default in val file
  lPrefs.ExplicitMaskName := '';
  lPrefs.ValFilename := '';
  lPrefs.Outname := '';
end;

(*function CheckBool (lPref, lFlag: integer): boolean;
//check if Flag is in lPref. For example, if Flag is 1 then returns true for all odd lPrefs
begin
    result := (lPref and lFlag) = lFlag;
end;    *)

function noVariance (lRA: singlep; lnSubj: integer): boolean;
var
   lI : integer;
begin
     result := false;
     if lnSubj < 2 then exit;
     for lI := 2 to lnSubj do
         if lRA^[1] <> lRA^[lI] then
            exit;
     result := true;
end;

function DoLesion (var lPrefs: TLDMPrefs): boolean;
  label
	666;
var
	lFact,lnFactors,lSubj,lnSubj,lnSubjAll,lMaskVoxels,lnCritV,lCritPctV: integer;
	lImageNames,lImageNamesAll:  TStrings;
        lPredictorList: TStringList;
	lTemp4D,lMaskname,lFactname: string;
	lMaskHdr: TMRIcroHdr;
        lMultiSymptomRA,lSymptomRA: singleP;
begin
  if (not lPrefs.BMtest) and (not lPrefs.ttest) and (not lPrefs.LTest) then begin
      MsgX('Error: you need to compute at least on test [options/test menu]');
      exit;
  end;
  lImageNamesAll:= TStringList.Create; //not sure why TStrings.Create does not work???
  lImageNames:= TStringList.Create; //not sure why TStrings.Create does not work???
  if not GetValCore(lPrefs.ValFilename, lnSubjAll,lnFactors,lMultiSymptomRA,lImageNamesAll,lnCritV,lCritPctV,lPredictorList) then begin
     MsgX('Error with VAL file');
     goto 666;
  end;
  if lPrefs.critPct < 0 then //-1 denotes using the values specified in the VAL file
     lPrefs.critPct := lCritPctV;
   lTemp4D := CreateDecompressed4D(lImageNamesAll);
  if (lnSubjAll < 1) or (lnFactors < 1) then begin
     MsgX('Not enough subjects ('+inttostr(lnSubjAll)+') or factors ('+inttostr(lnFactors)+').');
     goto 666;
  end;
  lMaskname := lImageNamesAll[0];
  if not NIFTIhdr_LoadHdr(lMaskname,lMaskHdr) then begin
	   MsgX('Error reading 1st mask.');
	   goto 666;
   end;
   lMaskVoxels := ComputeImageDataBytes8bpp(lMaskHdr);
   if (lMaskVoxels < 2) or (not CheckVoxels(lMaskname,lMaskVoxels,0)){make sure there is uncompressed .img file}  then begin
	   MsgX('Mask file size too small.');
	   goto 666;
   end;
  if (lPrefs.OutName = '') or (not DirExists(extractfiledir(lPrefs.Outname))) then begin
      lPrefs.Outname := extractfiledir(lPrefs.ValFilename)+pathdelim+'results.nii.gz';
      MsgX('Output stored as '+lPrefs.Outname);
  end;
   for lFact := 1 to lnFactors do begin
          ClearMsgX;
          MsgX(MainForm.GetKVers);
      lImageNames.clear;
       for lSubj := 1 to lnSubjAll do
           if (not lPrefs.LTest) or (lMultiSymptomRA^[lSubj+((lFact-1)*lnSubjAll)] = 0) OR (lMultiSymptomRA^[lSubj+((lFact-1)*lnSubjAll)] = 1) THEN begin
           {$IFNDEF FPC}if lMultiSymptomRA^[lSubj+((lFact-1)*lnSubjAll)] <> NaN then {$ENDIF}
              lImageNames.Add(lImageNamesAll[lSubj-1]);
           end else begin
               MsgX('Data rejected: behavior must be zero or one for binomial test '+lImageNamesAll.Strings[lSubj-1]);
           end;
       lnSubj := lImageNames.Count;
       if lnSubj > 2 then begin
          getmem(lSymptomRA,lnSubj * sizeof(single));
          lnSubj := 0;
          for lSubj := 1 to lnSubjAll do begin
            if (not lPrefs.LTest) or (lMultiSymptomRA^[lSubj+((lFact-1)*lnSubjAll)] = 0) OR (lMultiSymptomRA^[lSubj+((lFact-1)*lnSubjAll)] = 1) THEN begin
              {$IFNDEF FPC}if lMultiSymptomRA^[lSubj+((lFact-1)*lnSubjAll)] <> NaN then begin
              {$ELSE} begin{$ENDIF}
                 inc(lnSubj);
                 lSymptomRA^[lnSubj] := lMultiSymptomRA^[lSubj+((lFact-1)*lnSubjAll)];
              end; //valid value
            end; //not binomial, or 1/0
        end; //for each subject
            MsgX('Threads: '+inttostr(gnCPUThreads));
            lFactName := lPredictorList.Strings[lFact-1];
            lFactName := LegitFilename(lFactName,lFact);
            MsgX('Factor = '+lFactname);
            For lSubj := 1 to lnSubj do
                MsgX (lImageNames.Strings[lSubj-1] + ' = '+realtostr(lSymptomRA^[lSubj],2) );
            MsgX('Total voxels = '+inttostr(lMaskVoxels));
            lPrefs.nCrit := round( (lnSubj*lPrefs.CritPct)/100);
            MsgX('Only testing voxels damaged in at least '+inttostr(lPrefs.nCrit)+' individual[s]');
            MsgX('Number of Lesion maps = '+inttostr(lnSubj));
            if not CheckVoxelsGroupX(lImageNames,lMaskHdr {lMaskVoxels}) then begin
               MsgX('Error: File dimensions differ from mask.');
	       goto 666;
            end;
            if noVariance (lSymptomRA,lnSubj) then
               MsgX('Error no variability in behavioral data ')
            else
                TurboLDM (lImageNames, lMaskHdr, lPrefs, lSymptomRA, lFactname,lPrefs.OutName);
            Freemem(lSymptomRA);
       end else begin
          MsgX('At least 2 individuals required to compute statistics for '+lPredictorList.Strings[lFact-1]);
       end; //lnsubj > 2
          end; //for each factor
    if lnSubjAll > 0 then begin
       Freemem(lMultiSymptomRA);
    end;
    666:
    lImageNames.Free;
    lImageNamesAll.Free;
    lPredictorList.Free;
    DeleteDecompressed4D(lTemp4D);
end;

procedure ShowHelp;
begin
   MsgX('usage ''npm [options] -o resultsfilname  valfilename'' ');
   MsgX(' Options ');
   MsgX('   -c: critical percent 0..100 ');
   MsgX('   -p: permutations 0..4000 ');
   MsgX('   -t: Test [1=Liebermeister, 2=TTest, 4=BMtest, 6=t&BMtests');
   MsgX('   -o: Output filename');
   MsgX('examples:');
   MsgX('  npm -c 25 -p 1000 -o c:\results.nii.gz c:\mri\data.val');
   MsgX('  npm -c 25 -o "c:\program files\results.hdr" c:\mri\data.val');
end;

procedure ReadParamStr;
var
   lStr: String;
   I,lError: integer;
   lCommandChar: Char;
   lSingle: single;
   lHelpShown: boolean;
   lPrefs: TLDMPrefs;
begin
   if (ParamCount  < 1) then exit;
     SetDefaultPrefs(lPrefs);
  lHelpShown := false;
  lStr := paramstr(0);
  lStr := extractfilename(lStr);
  lStr := string(StrUpper(PChar(lStr))) ;
  if (ParamCount > 0) then begin
    I := 0;
    repeat
     lStr := '';
     repeat
        inc(I);
        if I = 1 then
            lStr := ParamStr(I)
        else begin
            if lStr <> '' then
               lStr := lStr +' '+ ParamStr(I)
            else
                lStr := ParamStr(I);
        end;
        if (length(lStr)>1) and (lStr[1] = '-') and (ParamCount > I) then begin //special command
           //-z= zoom, -f= format [png,jpeg,bmp], -o= output directory
           lCommandChar := UpCase(lStr[2]);
           inc(I);
           lStr := ParamStr(I);
           lStr := string(StrUpper(PChar(lStr))) ;
           case lCommandChar of
                'C','P','T': begin //CritPct
                     Val(lStr,lSingle,lError);
                     if lError = 0 then begin
                        if lCommandChar = 'C' then
                           lPrefs.CritPct := round(lSingle)
                        else if lCOmmandChar = 'P' then
                             lPrefs.nPermute := round(lSingle)
                        else if lCOmmandChar = 'T' then begin
                             case round(lSingle) of
                                  1: begin lPrefs.LTest := true; lPrefs.Ttest := false; lPrefs.BMtest := false; end;
                                  2: begin lPrefs.LTest := false; lPrefs.Ttest := true; lPrefs.BMtest := false; end;
                                  4: begin lPrefs.LTest := false; lPrefs.Ttest := false; lPrefs.BMtest := true; end;
                                  6: begin lPrefs.LTest := false; lPrefs.Ttest := true; lPrefs.BMtest := true; end;
                                  //1=Liebermeister, 2=TTest, 4=BMtest, 6=t&BMtests
                             end;//xxx
                        end;
                     end; //not lError
                end; //C= CritPct,P=permutations,T=test
                'O': begin //output filename
                      lPrefs.OutName :=lStr;
                end;

           end; //case lStr[2]
           lStr := '';
        end; //special command
     until (I=ParamCount) or (fileexists(lStr)) {or (gAbort)};
     if fileexists(lStr) then begin
        //lStr :=  GetLongFileName(lStr);
        lPrefs.ValFilename := lStr;
        //if lPrefs.OutName = '' then
        //   lPrefs.Outname := extractfiledir(paramstr(0))+pathdelim+'results.nii.gz';
        MsgX ('output ' + lPrefs.Outname);
        MsgX ('val file: '+lPrefs.ValFilename);
        
        DoLesion(lPrefs);
        MainForm.close;
     end else  begin
        MsgX('Error: unable to find '+lStr);
        if not lHelpShown then
            Showhelp;
        lHelpShown := true;
     end;
    until I >= ParamCount;
  end else begin
   ShowHelp;
  end;{param count > 0}
end;

end.
 