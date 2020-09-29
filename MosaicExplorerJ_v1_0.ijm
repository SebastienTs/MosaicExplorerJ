/////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:	MosaicExplorer
// Author: 	Sébastien Tosi (IRB/ADMCF)
// Version:	1.0
// Date:	28-09-2020
//	
// Description: An ImageJ script to align and stitch three-dimensional tiles and quickly 
//		explore terabyte-sized microscopy datasets.
//
// Usage: 	See documentation at https://github.com/SebastienTs/MosaicExplorerJ
//
/////////////////////////////////////////////////////////////////////////////////////////////

// Tiles: 3D Images / subfolders / 2D Images naming convention
XString = "--X";XDigits = 2;		// Tile grid X coordinate
YString = "--Y";YDigits = 2;		// Tile grid Y coordinate
CString = "--C";CDigits = 2;		// Channel short name (starts at 0)
RLString = "RL";RLDigits = 2;		// Illumination side (0/1)
// Additional file naming convention for 2D images
ZString = "Zb00--Z";ZDigits = 4;	// Z coordinate
CAMString = "CAM"; 			// Camera side (1/2)
// Default channel long names
ChanStr = newArray("C00--L05","C01--L06","XXX--XXX","XXX--XXX","XXX--XXX","XXX--XXX","XXX--XXX","XXX--XXX");

// Close all images
run("Close All");

// Root folder of the scan
RootFolder = getDirectory("Select scan root folder");

// Dialog box: scan configuration
Dialog.create("Scan configuration");
Dialog.addNumber("Tile width (pix)",2048);
Dialog.addNumber("Tile height (pix)",2048);
Dialog.addNumber("Side margins (pix)",512);
for(c=0;c<8;c++)Dialog.addString("Channel "+d2s(c,0),ChanStr[c]);
Dialog.addCheckbox("Dual side",false);
Dialog.addCheckbox("Dual camera",false);
Dialog.addCheckbox("Color mode",true);
Dialog.show();
ImageWidth = Dialog.getNumber();
ImageHeight = Dialog.getNumber();
SideMargins = Dialog.getNumber();
for(c=0;c<8;c++)ChanStr[c] = Dialog.getString();
DualSide = Dialog.getCheckbox();
DualCAM = Dialog.getCheckbox();
EnableColorMode = Dialog.getCheckbox();

// Check if the 3D tiles are subfolders of 2D tif files or multi-tiff files
FileList = getFileList(RootFolder);
FolderMode = false;
for(i=0;i<lengthOf(FileList);i++)if(endsWith(FileList[i],'/'))FolderMode = true;

// Check if a configuration file is already saved in the root folder
tst = File.exists(RootFolder+"ScanStitch.csv");
if(tst)UseFileParams = getBoolean("Import existing tile grid settings?");
else UseFileParams = 0;

// Tile grid alignment parameters
OverlapX = newArray(0,0,0,0);
OverlapY = newArray(0,0,0,0);
CorrX = newArray(0,0,0,0);
CorrY = newArray(0,0,0,0);
CorrZX = newArray(0,0,0,0);
CorrZY = newArray(0,0,0,0);
MaxInt = newArray(2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047);
CAMAng = newArray(0,0);
CAMSca = newArray(1,1);
CAMXCor = newArray(0,0);
CAMYCor = newArray(0,0);
RLXCor = newArray(0,0);
RLYCor = newArray(0,0);
CropFracWidth = 0;  // Fractional crop width of left side last column / right side first column
RLZCor = newArray(0,0);
RegRight = false;
OverlayCAM1 = false;
CAMOverlay = false;
Steps = 1;
BigSteps = 5;
NudgeMode = false;

// Load tile grid alignment parameters from configuration file (if present)
if(UseFileParams)
{
	RawParams = File.openAsString(RootFolder+"ScanStitch.csv");
	RawParams = split(RawParams,"\n");
	// Main parameters are on first line
	FirstLine = RawParams[0];
	Params = split(FirstLine,",");
	FloatParams = newArray(lengthOf(Params));
	for(i=0;i<lengthOf(Params);i++)FloatParams[i] = parseFloat(Params[i]);
	if(DualSide == false)
	{
		Nprm = 24;
		if(lengthOf(Params)!=48)exit("Saved parameters are not for single side experiment");	
	}
	else
	{
		Nprm = 28;
		if(lengthOf(Params)!=56)exit("Saved parameters are not for dual side experiment");
	}
	// Loop over sides (tile grid alignment is independent for both sides, and bot cameras)
	for(s=0;s<=1;s++)
	{
		OverlapX[0+2*s] = FloatParams[0+Nprm*s];	// Camera 1
		OverlapX[1+2*s] = FloatParams[1+Nprm*s];	// Camera 2
		OverlapY[0+2*s] = FloatParams[2+Nprm*s];
		OverlapY[1+2*s] = FloatParams[3+Nprm*s];
		CorrX[0+2*s] = FloatParams[4+Nprm*s];
		CorrX[1+2*s] = FloatParams[5+Nprm*s];
		CorrY[0+2*s] = FloatParams[6+Nprm*s];
		CorrY[1+2*s] = FloatParams[7+Nprm*s];
		CorrZX[0+2*s] = FloatParams[8+Nprm*s];
		CorrZX[1+2*s] = FloatParams[9+Nprm*s];
		CorrZY[0+2*s] = FloatParams[10+Nprm*s];
		CorrZY[1+2*s] = FloatParams[11+Nprm*s];
		for(c=0;c<8;c++)MaxInt[c+8*s] = FloatParams[12+c+Nprm*s];
		CAMAng[s] = FloatParams[20+Nprm*s];
		CAMSca[s] = FloatParams[21+Nprm*s];
		CAMXCor[s] = FloatParams[22+Nprm*s];
		CAMYCor[s] = FloatParams[23+Nprm*s];
		if(DualSide==1)
		{
			c = s; // Here, loop is over cameras, not sides
			RLXCor[c] = FloatParams[24+Nprm*c];
			RLYCor[c] = FloatParams[25+Nprm*c];
			RLZCor[c] = FloatParams[26+Nprm*c];
			CropFracWidth = FloatParams[27+Nprm*c];
		}
	}
	// Free Zxy correction is on second line (if used)
	if(lengthOf(RawParams)>1)
	{
		SecondLine = RawParams[1];
		Params2 = split(SecondLine,",");
		ZManOffs = newArray(lengthOf(Params2));
		for(i=0;i<lengthOf(Params2);i++)ZManOffs[i] = parseFloat(Params2[i]);
		FreeZxyCorr = true;
	}
	else 
	{
		ZManOffs = newArray(1);
		FreeZxyCorr = false;
	}
}
else 
{
	ZManOffs = newArray(1);
	FreeZxyCorr = false;
}

// Init
if(isOpen("ROI Manager"))
{
	selectWindow("ROI Manager");
	run("Close");
}
ColorMode = EnableColorMode;		// Color-code adjacent fields of view
ReDraw = true;				// Redraw current slice
StitchMode = "Add";			// Tile copy mode
CCur = 0;				// Current channel
CamCur = 1;				// Current camera
SidCur = 1;				// Current illumination side
ShowDual = DualSide;			// Display both illumination sides
ExportStack = 0;			// Export tile grid to folder
Exit = false;				// Exit macro
ZMax = NaN;				// Last slice

// Parse filenames to retrieve grid configuration
FileList = getFileList(RootFolder);

// Find tile grid minimum and maximum X/Y/Z/C
XMin = 1/0;YMin = 1/0;XMax = 0;YMax = 0;CMin = 1/0; CMax = 0;Test = false;
if(FolderMode)FilterStr = "/";
else FilterStr = ".tif";
for(i=0;i<lengthOf(FileList);i++)
{
	if(endsWith(FileList[i],FilterStr))
	{
		// Only for first tile / folder
		if(Test == false)
		{
			if(FolderMode)
			{
				FolderNameTemplate = FileList[i];
				FileList2 = getFileList(RootFolder+FileList[i]);
				FileNameTemplate = FileList2[0];
				FirstFileName = FileList2[0];
				LastFileName = FileList2[lengthOf(FileList2)-1];
				ZMax = parseInt(substring(LastFileName,indexOf(LastFileName,ZString)+lengthOf(ZString),indexOf(LastFileName,ZString)+lengthOf(ZString)+ZDigits));
				ZMin = parseInt(substring(FirstFileName,indexOf(FirstFileName,ZString)+lengthOf(ZString),indexOf(FirstFileName,ZString)+lengthOf(ZString)+ZDigits));
			}
			else
			{
				FolderNameTemplate = "";
				FileNameTemplate = FileList[i];
				ZMin = 0;
				setBatchMode(true);
				run("TIFF Virtual Stack...", "open="+RootFolder+FileList[i]);
				ZMax = nSlices/(DualCAM+1)-1;
				close();
				setBatchMode("exit & display");
			}
			ZCur = round((ZMax+ZMin)/2);
			Test = true;
		}
		Name = FileList[i];
		Idx = indexOf(Name,XString);
		XInd = parseInt(substring(Name,Idx+lengthOf(XString),Idx+lengthOf(XString)+XDigits));
		Idx = indexOf(Name,YString);
		YInd = parseInt(substring(Name,Idx+lengthOf(YString),Idx+lengthOf(YString)+YDigits));
		Idx = indexOf(Name,CString);
		CInd = parseInt(substring(Name,Idx+lengthOf(CString),Idx+lengthOf(CString)+CDigits));
		XMin = minOf(XMin,XInd);
		YMin = minOf(YMin,YInd);
		CMin = minOf(CMin,CInd);
		XMax = maxOf(XMax,XInd);
		YMax = maxOf(YMax,YInd);
		CMax = maxOf(CMax,CInd);
		// Bounds of currently displayed tile grid
		XdMin = XMin;	
		XdMax = XMax;
		YdMin = YMin;
		YdMax = YMax;
	}
}

// Check that a tile grid has been detected
if((Test==false)||(isNaN(ZMax)))exit("Invalid root folder");

// Last diaplayed tile center tables
XTile = newArray((XMax-XMin+1)*(YMax-YMin+1)*2);
YTile = newArray((YMax-YMin+1)*(YMax-YMin+1)*2);
XiTile = newArray((XMax-XMin+1)*(YMax-YMin+1)*2);
YiTile = newArray((YMax-YMin+1)*(YMax-YMin+1)*2);

// Check that number of channels does not exceed 8
if(CMax>8)
{
	showMessage("Only up to 8 channels supported");
	exit;
}

// Initialize manual Zxy correction if not loaded from file
if(lengthOf(ZManOffs)==1)ZManOffs = newArray((XMax+1-XMin)*(YMax+1-YMin)*4); 

// Assign default alignment for right side tile grids when no configuration file is loaded (no overlap)
if(!UseFileParams)
{
	RLXCor[0] = ImageWidth*(XMax-XMin+1)*DualSide;
	RLXCor[1] = ImageWidth*(XMax-XMin+1)*DualSide;
}

// Create board
if(EnableColorMode == true)newImage("Board", "RGB black", ImageWidth*(XMax-XMin+1)*(DualSide+1)+2*SideMargins, ImageHeight*(YMax-YMin+1)+2*SideMargins, 1);
else newImage("Board", "16-bit black", ImageWidth*(XMax-XMin+1)*(DualSide+1)+2*SideMargins, ImageHeight*(YMax-YMin+1)+2*SideMargins, 1);
BoardID = getImageID();

// Main loop
while(isOpen(BoardID))
{
	if(ReDraw == true)
	{
		// Cleanup and initialize
		selectImage(BoardID);
		if(FreeZxyCorr==false)rename("Board (Z="+d2s(ZCur,0)+" CorrZx="+d2s(CorrZX[CamCur-1+2*(SidCur-1)],0)+" CorrZy="+d2s(CorrZY[CamCur-1+2*(SidCur-1)],0)+")");
		else 
		{
			ZdMax = ZManOffs[YdMax+XdMax*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)];
			rename("Board (Z="+d2s(ZCur,0)+" CorZxy="+d2s(ZdMax,0)+" @LowerRight)");
		}
		run("Select All");
		run("Clear");
		run("Select None");
		setTool("zoom");
		setBatchMode(true);

		// Ramp blending should use "add" copy/paste
		StitchModeCopy = StitchMode;
		if(StitchModeCopy=="Ramp")StitchModeCopy = "Add";
		setPasteMode(StitchModeCopy);
		
		// Additional loop for dual side mode
		SidMin=SidCur;SidMax=SidCur;
		if(ShowDual==true)
		{
			SidMin = 1;
			SidMax = 2;	
		}
		
		// Create Ramp Mask if needed
		if(StitchMode=="Ramp")
		{
			BlendMask(ImageWidth,OverlapX[CamCur-1]/100,OverlapY[CamCur-1]/100);
			selectImage(BoardID);
		}
		
		// Paste all images from tile grid
		for(SidCur2=SidMin;SidCur2<=SidMax;SidCur2++)
		{
			
			// Effective XY size of a tile without overlap
			CropWidth = round(ImageWidth*(100-OverlapX[CamCur-1+2*(SidCur2-1)])/100);
			CropHeight = round(ImageHeight*(100-OverlapY[CamCur-1+2*(SidCur2-1)])/100);
			
			for(j=YdMin;j<=YdMax;j++)
			{
				for(i=XdMin;i<=XdMax;i++)
				{
					// Update filename to load correct file
					ImageName = replace(FileNameTemplate, XString+IJ.pad(XMin,XDigits), XString+IJ.pad(i,XDigits));
					ImageName = replace(ImageName, YString+IJ.pad(YMin,YDigits), YString+IJ.pad(j,YDigits));
					ImageName = replace(ImageName, RLString+IJ.pad(0,RLDigits), RLString+IJ.pad(SidCur2-1,RLDigits));
					
					// Acount for Z correction
					if(FreeZxyCorr)ZCorrected = ZCur+RLZCor[CamCur-1]*(SidCur2-1)+ZManOffs[j+i*(YMax+1-YMin)+(SidCur2-1)*(YMax+1-YMin)*(XMax+1-XMin)]+RLZCor[CamCur-1]*(SidCur2-1);  // Manual ZOffs
					else ZCorrected = ZCur+CorrZX[CamCur-1+2*(SidCur2-1)]*i+CorrZY[CamCur-1+2*(SidCur2-1)]*j+RLZCor[CamCur-1]*(SidCur2-1); // Linear ZOffs
	
					// Tiles are stored as folders of images
					if(FolderMode)
					{
						ImageName = replace(ImageName, ChanStr[0], ChanStr[CCur]);
						ImageName = replace(ImageName, CAMString+"1", CAMString+d2s(CamCur,0));
						ImageName = replace(ImageName, ZString+IJ.pad(ZMin,ZDigits), ZString+IJ.pad(ZCorrected,ZDigits));
						FolderName = replace(FolderNameTemplate, XString+IJ.pad(XMin,XDigits), XString+IJ.pad(i,XDigits));
						FolderName = replace(FolderName, YString+IJ.pad(YMin,YDigits), YString+IJ.pad(j,YDigits));
						FolderName = replace(FolderName, CString+IJ.pad(0,CDigits), CString+IJ.pad(CCur,CDigits));
						FolderName = replace(FolderName, RLString+IJ.pad(0,RLDigits), RLString+IJ.pad(SidCur2-1,RLDigits));
						// If an image is not found display a black image of same size instead
						if(File.exists(RootFolder+FolderName+ImageName))open(RootFolder+FolderName+ImageName);
						else newImage("Black", "16-bit black", ImageWidth, ImageHeight, 1);
					}
					else // Tiles are stored as 3D multi-TIFF files
					{
						ImageName = replace(ImageName, CString+IJ.pad(0,CDigits), CString+IJ.pad(CCur,CDigits));
						// If an image is not found display a black image of same size instead
						if((ZCorrected>0)&&(ZCorrected<ZMax)&&File.exists(RootFolder+ImageName))open(RootFolder+ImageName,1+ZCorrected+ZMax*(CamCur-1)*DualCAM);
						else newImage("Black", "16-bit black", ImageWidth, ImageHeight, 1);
					}
	
					// Apply intensity correction to right side for dual side mode and different saturation intensity settings
					if((DualSide)&&(MaxInt[CCur+8]/MaxInt[CCur]!=1)&&(SidCur2==2))run("Multiply...", "value="+d2s(MaxInt[CCur]/MaxInt[CCur+8],4));
	
					// Apply tile blending ramp
					if(StitchMode=="Ramp")
					{
						rename("Img");
						run("32-bit");
						imageCalculator("Multiply","Img","Mask");
						setMinAndMax(0,65535);
						run("16-bit");
					}
					
					// Color mode: color-code adjacent fields of view with alternating red/green
					if(EnableColorMode==true)
					{
						if((ColorMode==true)&&(OverlayCAM1==false))
						{
							if((((j-YdMin)%2)==0)^(((i-XdMin)%2)==0)^(((SidCur2-1)==0)&&((XMax+1-XMin)%2==1))^(CamCur==1))run("Green");
							else run("Red");	
						}
						else
						{ 
							if(OverlayCAM1==true)run("Green");
							else run("Grays");
						}
						if(DualSide)setMinAndMax(0,MaxInt[CCur]);
						else setMinAndMax(0,MaxInt[CCur+8*(SidCur2-1)]);
						run("RGB Color");
					}
					
					// Flip image horizontally for second camera			
					if(CamCur == 2)run("Flip Horizontally");	
						
					// Optionally apply cropping to right side tile grid to reduce overlap
					if((ShowDual)&&(CropFracWidth!=0))
					{
						if((i==XdMax)&&(SidCur2==1))
						{
							makeRectangle(ImageWidth-round(ImageWidth*CropFracWidth),0,ImageWidth,ImageHeight);
							run("Clear", "slice");
							run("Select None");
						}
						if((i==XdMin)&&(SidCur2==2))
						{
							makeRectangle(0,0,round(ImageWidth*CropFracWidth),ImageHeight);
							run("Clear", "slice");
							run("Select None");
						}
					}
	
					// Copy the image
					run("Select None");
					run("Copy");
					close();
					
					// Paste the image at the correct location in the tile grid
					makeRectangle(CropWidth*(i-XMin)-CorrX[CamCur-1+2*(SidCur2-1)]*j+SideMargins+RLXCor[CamCur-1]*(SidCur2-1),CropHeight*(j-YMin)-CorrY[CamCur-1+2*(SidCur2-1)]*i+SideMargins+RLYCor[CamCur-1]*(SidCur2-1),ImageWidth,ImageHeight);
					run("Paste");
				}
			}

			// Ensure no selection is active
			run("Select None");
			
			// Intensity saturation adjustment for grayscale mode
			if(EnableColorMode==false)
			{
				if(DualSide)setMinAndMax(0,MaxInt[CCur]);
				else setMinAndMax(0,MaxInt[CCur+8*(SidCur2-1)]);
			}
			
		} // End of tile pasting loop

		// Compute all possible tile positions for both sides
		cnt = 0;
		for(SidCur2=1;SidCur2<=2;SidCur2++)
		{
			for(j=0;j<=YMax;j++)
			{
				for(i=0;i<=XMax;i++)
				{
					XTile[cnt] = CropWidth*(i-XMin)-CorrX[CamCur-1+2*(SidCur2-1)]*j+SideMargins+RLXCor[CamCur-1]*(SidCur2-1)+ImageWidth/2;
					YTile[cnt] = CropHeight*(j-YMin)-CorrY[CamCur-1+2*(SidCur2-1)]*i+SideMargins+RLYCor[CamCur-1]*(SidCur2-1)+ImageHeight/2;
					XiTile[cnt] = i;
					YiTile[cnt] = j;
					cnt++;
				}
			}
		}
		
		// Apply CAM2 tilt and scaling if CAM1 overlay is active
		if((isOpen("CAM1"))&&(CamCur==2))
		{
			if(CAMAng[SidCur-1]!=0)run("Rotate... ", "angle="+d2s(CAMAng[SidCur-1],2)+" grid=1 interpolation=None");
			if(CAMSca[SidCur-1]!=1)run("Scale...", "x="+d2s(CAMSca[SidCur-1],4)+" y="+d2s(CAMSca[SidCur-1],4)+" interpolation=Bilinear average");
			if((CAMXCor[SidCur-1]!=0)||(CAMYCor[SidCur-1]!=0))run("Translate...", "x="+d2s(CAMXCor[SidCur-1],0)+" y="+d2s(CAMYCor[SidCur-1],0)+" interpolation=None");
		}
		if((isOpen("CAM1"))&&(CAMOverlay==true))
		{
			run("Remove Overlay");
			run("Add Image...", "image=CAM1 x=0 y=0 opacity=50");
		}

		// Close intensity ramp mask if opened
		if(StitchMode=="Ramp")
		{
			selectImage("Mask");
			close();
			selectImage(BoardID);
		}

		// Exit batch mode
		setBatchMode("exit & display");
		ReDraw = false;
	}

	// Swap between single and big steps for Z nudging
	if(isKeyDown("space"))
	{
		if(Steps == 1)
		{
			Steps = BigSteps;
			showStatus("Steps: "+d2s(BigSteps,0));
		}
		else
		{
			if(Steps == BigSteps)
			{
				Steps = 1;
				showStatus("Steps: 1");
			}
		}
		
		// Wait space to be released
		while(isKeyDown("space"))wait(50);	
	}

	// Shortcut to nudge Z slice and Z correction
	if(isKeyDown("shift"))
	{
		// Use mouse coordinates to locate active tile
		getCursorLoc(x, y, z, flags);
		
		// Avoid pressing space returns -1/-1 coordinate
		if(x>-1)
		{
			mindst = 1/0;
			minidx = 0;
			N = lengthOf(XTile)/2;
			for(i=(SidCur-1)*N;i<SidCur*N;i++)
			{
				dst = sqrt(pow(x-XTile[i],2)+pow(y-YTile[i],2));
				if(dst<mindst)
				{
					mindst = dst;
					minidx = i;
				}
			}
			
			// Nudge CorrZx (global or column)
			if(XiTile[minidx]>XdMin)
			{
				if(x<XTile[minidx])
				{
					XdMin = XiTile[minidx]-1;
					YdMin = YiTile[minidx];
					XdMax = XiTile[minidx];
					YdMax = YiTile[minidx];
					if(NudgeMode == true)
					{
						if(FreeZxyCorr==false)CorrZX[CamCur-1+2*(SidCur-1)] = CorrZX[CamCur-1+2*(SidCur-1)] + (-Steps+2*Steps*(y<=YTile[minidx]));
						else for(i=XiTile[minidx];i<=(XMax-XMin);i++)for(j=YiTile[minidx];j<=(YMax-YMin);j++)ZManOffs[j+i*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)] = ZManOffs[j+i*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)] + (-Steps+2*Steps*(y<=YTile[minidx]));
						//else for(i=XiTile[minidx];i<=(XMax-XMin);i++)for(j=0;j<=(YMax-YMin);j++)ZManOffs[j+i*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)] = ZManOffs[j+i*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)] + (-Steps+2*Steps*(y<=YTile[minidx]));
					}
					else showStatus("Tile adjustment mode");
					ShowDual = false;
					ReDraw = true;
					NudgeMode = true;
				}
			}
			
			// Nudge CorrZy (global or row)
			if(YiTile[minidx]>YdMin)
			{
				if(y<YTile[minidx])
				{
					XdMin = XiTile[minidx];
					YdMin = YiTile[minidx]-1;
					XdMax = XiTile[minidx];
					YdMax = YiTile[minidx];
					if(NudgeMode == true)
					{
						if(FreeZxyCorr==false)CorrZY[CamCur-1+2*(SidCur-1)] = CorrZY[CamCur-1+2*(SidCur-1)] + (-Steps+2*Steps*(x>XTile[minidx]));
						else for(j=YiTile[minidx];j<=(YMax-YMin);j++)for(i=XiTile[minidx];i<=(XMax-XMin);i++)ZManOffs[j+i*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)] = ZManOffs[j+i*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)] + (-Steps+2*Steps*(x>XTile[minidx]));
						//else for(j=YiTile[minidx];j<=(YMax-YMin);j++)for(i=0;i<=(XMax-XMin);i++)ZManOffs[j+i*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)] = ZManOffs[j+i*(YMax+1-YMin)+(SidCur-1)*(YMax+1-YMin)*(XMax+1-XMin)] + (-Steps+2*Steps*(x>XTile[minidx]));
					}
					ShowDual = false;
					ReDraw = true;
					NudgeMode = true;
				}
			}
	
			// Actions from left uppermost visible tile
			if((XiTile[minidx]==XdMin)&&(YiTile[minidx]==YdMin))
			{
				// Nudge current Z slice
				ZCur = ZCur + (-1+2*(x>XTile[minidx]))*Steps;
				ReDraw = true;	
			}
		}
		else showStatus("Move mouse");

		// Wait shift to be released
		while(isKeyDown("shift"))wait(50);
	}
	
	// Open configuration panel
	if(isKeyDown("alt"))
	{
		//Exit nudge mode and restore complete grid
		if(NudgeMode==true)
		{
			XdMin = XMin;
			YdMin = YMin;
			XdMax = XMax;
			YdMax = YMax;
			ReDraw = true;
			NudgeMode = false;
		}
		else
		{	
		// Dialog box: control panel
		OldColorMode = ColorMode;
		CamCurOld = CamCur;
		CCurOld = CCur;
		SidCurOld = SidCur;
		Dialog.create("Control Panel");
		Dialog.addSlider("ZPos", ZMin, ZMax, ZCur);
		Dialog.addSlider("CPos", 0, CMax, CCur);
		Dialog.addSlider("MaxInt", 1, 65535, MaxInt[CCur+8*(SidCur-1)]);
		Dialog.addSlider("CAM", 1, DualCAM+1, CamCur);
		Dialog.addSlider("Side", 1, DualSide+1, SidCur);
		Dialog.addChoice("Stitch Mode", newArray("Add","Copy","Max","Ramp"),StitchMode);
		Dialog.addNumber("OvlX (%)", OverlapX[CamCur-1+2*(SidCur-1)]);
		Dialog.addNumber("OvlY (%)", OverlapY[CamCur-1+2*(SidCur-1)]);
		Dialog.addNumber("XCor", CorrX[CamCur-1+2*(SidCur-1)]);
		Dialog.addNumber("YCor", CorrY[CamCur-1+2*(SidCur-1)]);
		Dialog.addMessage("ZxyCor (Camera Common)");
		if(FreeZxyCorr==false)
		{
			Dialog.addNumber("ZxCor", CorrZX[CamCur-1+2*(SidCur-1)]);
			Dialog.addNumber("ZyCor", CorrZY[CamCur-1+2*(SidCur-1)]);
		}
		else
		{
			cnt=(SidCur-1)*(XMax+1-XMin)*(YMax+1-YMin);
			for(i=XMin;i<=XMax;i++)
			{
				Str="";
				for(j=YMin;j<=YMax;j++)
				{
					Str=Str+IJ.pad(ZManOffs[cnt],3);
					if(j<YMax)Str=Str+",";
					cnt++;
				}
				Dialog.addString("Col"+IJ.pad(i,2),Str,32);
			}
		}
		if(DualSide)Dialog.addNumber("ZRLCor", RLZCor[CamCur-1]);
		if(DualSide)Dialog.addCheckbox("Dual side mode", ShowDual);
		if(EnableColorMode == true)Dialog.addCheckbox("Color mode", ColorMode);
		Dialog.addCheckbox("Free Zxy Correction", FreeZxyCorr);
		if(selectionType()==5)Dialog.addCheckbox("Register OvlX & YCor --> OvlY & XCorr", false);
		if(selectionType()==5)Dialog.addCheckbox("Register OvlY & XCor only", false);
		Dialog.addCheckbox("Grid+CAM+LR Panel", false);
		Dialog.addCheckbox("Export stack", false);
		Dialog.addCheckbox("Exit", false);
		Dialog.show();
		ZCur = Dialog.getNumber();
		CCur = Dialog.getNumber();
		MaxInt[CCurOld+8*(SidCurOld-1)] = Dialog.getNumber();
		CamCur = Dialog.getNumber();
		SidCur = Dialog.getNumber();
		StitchMode = Dialog.getChoice();
		OverlapX[CamCurOld-1+2*(SidCurOld-1)] = Dialog.getNumber();
		OverlapY[CamCurOld-1+2*(SidCurOld-1)] = Dialog.getNumber();
		CorrX[CamCurOld-1+2*(SidCurOld-1)] = Dialog.getNumber();
		CorrY[CamCurOld-1+2*(SidCurOld-1)] = Dialog.getNumber();
		if(FreeZxyCorr==false)
		{
			CorrZX[CamCurOld-1+2*(SidCurOld-1)] = Dialog.getNumber();
			CorrZY[CamCurOld-1+2*(SidCurOld-1)] = Dialog.getNumber();
		}
		else
		{
			cnt=(SidCurOld-1)*(XMax+1-XMin)*(YMax+1-YMin);
			for(i=XMin;i<=XMax;i++)
			{
				Str = Dialog.getString;
				Str = split(Str,",");
				if(lengthOf(Str)==(YMax+1-YMin))
				{
					for(j=0;j<=YMax-YMin;j++)
					{
						ZManOffs[cnt] = parseInt(Str[j]);
						cnt++;
					}
				}
				else 
				{
					for(j=0;j<=YMax-YMin;j++)
					{
						ZManOffs[cnt] = 0;
						cnt++;
					}
				}
			}
		}
		if(DualSide)RLZCor[CamCurOld-1] = Dialog.getNumber();
		if(DualSide)ShowDual = Dialog.getCheckbox();
		if(EnableColorMode == true)ColorMode = Dialog.getCheckbox();
		FreeZxyCorr = Dialog.getCheckbox();
		if(selectionType()==5)RegOvlX = Dialog.getCheckbox();
		if(selectionType()==5)RegOvlY = Dialog.getCheckbox();
		ShowExtra = Dialog.getCheckbox();
		ExportStack = Dialog.getCheckbox(); 
		Exit = Dialog.getCheckbox();
		
		// Wait alt to be released
		while(isKeyDown("alt"))wait(50);
		
		// Trigger board redraw
		ReDraw = true;

		// Grid+CAM+LR Panel dialog box
		if(ShowExtra)
		{
			Dialog.create("Grid+CAM+LR Panel");
			Dialog.addSlider("XdMin", XMin, XMax, XdMin);
			Dialog.addSlider("XdMax", XMin, XMax, XdMax);
			Dialog.addSlider("YdMin", YMin, YMax, YdMin);
			Dialog.addSlider("YdMax", YMin, YMax, YdMax);
			Dialog.addNumber("BigSteps", BigSteps);
			Dialog.addMessage("CAM2 registration");
			Dialog.addNumber("CAM2XCor", CAMXCor[SidCurOld-1]);
			Dialog.addNumber("CAM2YCor", CAMYCor[SidCurOld-1]);
			Dialog.addNumber("CAM2Angle", CAMAng[SidCurOld-1]);
			Dialog.addNumber("CAM2Scale", CAMSca[SidCurOld-1]);
			if((CamCur==1)&&(!isOpen("CAM1")))Dialog.addCheckbox("Overlay CAM1", OverlayCAM1);
			if((CamCur==1)&&(!isOpen("CAM1")))Dialog.addCheckbox("Start CAM2 registration", false);
			if(CamCur==2)
			{	
				if(selectionType()==10)
				{
					getSelectionCoordinates(XCAM1,YCAM1);
					if(lengthOf(XCAM1)==2)Dialog.addCheckbox("Register CAM2 Tilt & Scaling", false);
					if(lengthOf(XCAM1)==1)Dialog.addCheckbox("Register CAM2 XY Position", false);
				}
				else 
				{
					if(isOpen("CAM1"))Dialog.addCheckbox("Close CAM1", false);
				}
			}
			if(DualSide)
			{
				Dialog.addMessage("Right grid registration");
				Dialog.addNumber("RLXCor", RLXCor[CamCur-1]);
				Dialog.addNumber("RLYCor", RLYCor[CamCur-1]);
				Dialog.addNumber("CropX", CropFracWidth);	
				Dialog.addCheckbox("Register RL", false);
			}
			Dialog.show();
			XdMin = Dialog.getNumber();
			XdMax = Dialog.getNumber();
			YdMin = Dialog.getNumber();
			YdMax = Dialog.getNumber();
			BigSteps = Dialog.getNumber();
			CAMXCor[SidCurOld-1] = Dialog.getNumber();
			CAMYCor[SidCurOld-1] = Dialog.getNumber();
			CAMAng[SidCurOld-1] = Dialog.getNumber();
			CAMSca[SidCurOld-1] = Dialog.getNumber();
			if((CamCur==1)&&(!isOpen("CAM1")))OverlayCAM1 = Dialog.getCheckbox;
			else OverlayCAM1 = false;
			if(((CamCur==1)&&(!isOpen("CAM1")))||((CamCur==2)&&(isOpen("CAM1"))))RegCAM = Dialog.getCheckbox;
			else RegCAM = false;
			if(DualSide==1)
			{
				RLXCor[CamCur-1] = Dialog.getNumber();
				RLYCor[CamCur-1] = Dialog.getNumber();
				CropFracWidth = Dialog.getNumber();
				RegRight = Dialog.getCheckbox;
			}
			
			// Overlay CAM1 on top of CAM2
			if(OverlayCAM1)
			{
				if(!isOpen("CAM1"))
				{
					// Display CAM1 window
					run("Select None");
					run("Duplicate...", "title=CAM1");
					run("8-bit");
					run("Red");
					CAMOverlay = true;
					CamCur = 2; // Automatically switch to CAM2
					selectImage(BoardID);
				}	
			}
			
			// Regitser CAM2
			if(RegCAM == true)
			{
				if(CamCur==1)
				{
					// Display CAM1 window + reset CAM2 registration
					if(!isOpen("CAM1"))
					{
						CAMXCor[SidCurOld-1] = 0;
						CAMYCor[SidCurOld-1] = 0;
						CAMAng[SidCurOld-1] = 0;
						CAMSca[SidCurOld-1] = 1;
						run("Select None");
						run("Duplicate...", "title=CAM1");
						run("8-bit");
						run("Red");
						CAMOverlay = false;
						CamCur = 2; // Automatically switch to CAM2
						selectImage(BoardID);
					}
				}
				else // Two step registration: Tilt + scaling for two active points, XY alignment for one active point
				{
					if(isOpen("CAM1"))
					{
						Do = 0;					
						selectImage("CAM1");
						if(selectionType()==10)getSelectionCoordinates(XCAM1,YCAM1);
						run("Select None");
						selectImage(BoardID);
						if(selectionType()==10)
						{
							getSelectionCoordinates(XCAM2,YCAM2);
							if((lengthOf(XCAM2)==2)&&(lengthOf(XCAM1)==2))Do = 1;	// Register tilt and scaling
							if((lengthOf(XCAM2)==1)&&(lengthOf(XCAM1)==1))Do = 2;	// Register XY
						}
						run("Select None");
						if(Do == 0)  // Close CAM1 window and remove overlay
						{
							selectImage("CAM1");
							close();
							selectImage(BoardID);
							run("Remove Overlay");
						}
						if(Do == 1) // Register CAM2 tilt and scaling
						{
							Dst1 = sqrt(pow(XCAM1[1]-XCAM1[0],2)+pow(YCAM1[1]-YCAM1[0],2));
							Dst2 = sqrt(pow(XCAM2[1]-XCAM2[0],2)+pow(YCAM2[1]-YCAM2[0],2));
							Ang1 = atan((YCAM1[1]-YCAM1[0])/(XCAM1[1]-XCAM1[0]));
							Ang2 = atan((YCAM2[1]-YCAM2[0])/(XCAM2[1]-XCAM2[0]));
							CAMAng[SidCurOld-1] = (Ang1-Ang2)*180/PI;
							CAMSca[SidCurOld-1] = Dst1/Dst2;
						}
						if(Do == 2) // Register CAM2 XY position
						{
							CAMYCor[SidCurOld-1] = YCAM1[0]-YCAM2[0];
							CAMXCor[SidCurOld-1] = XCAM1[0]-XCAM2[0];
							CAMOverlay = true;
						}
						
					}
					else waitForUser("Take CAM1 snapshot first");
				}
			}
			
			// If a line selection is active and side registration is active, use it to register right tile grid
			if((selectionType()==5)&&((RegRight==true)))
			{
				getSelectionCoordinates(xpoints, ypoints);
				DX = xpoints[1]-xpoints[0];
				DY = ypoints[1]-ypoints[0];
				RLYCor[CamCur-1] = RLYCor[CamCur-1] + DY;
				RLXCor[CamCur-1] = RLXCor[CamCur-1] + DX;
			}			
		}
		
		// If a line selection is active, use it to align tile grid
		if((selectionType()==5)&&(ShowExtra==false))
		{
			getSelectionCoordinates(xpoints, ypoints);
			DX = xpoints[0]-xpoints[1];
			DY = ypoints[0]-ypoints[1];
			if(RegOvlX == true)
			{	
				OverlapX[CamCur-1+2*(SidCur-1)]  = OverlapX[CamCur-1+2*(SidCur-1)] + 100*DX/ImageWidth;
				OverlapY[CamCur-1+2*(SidCur-1)]  = OverlapX[CamCur-1+2*(SidCur-1)];
				CorrY[CamCur-1+2*(SidCur-1)] = CorrY[CamCur-1+2*(SidCur-1)] + DY;
				CorrX[CamCur-1+2*(SidCur-1)] = -CorrY[CamCur-1+2*(SidCur-1)];
			}
			if((RegOvlY == true)&&(RegOvlX == false))
			{
				OverlapY[CamCur-1+2*(SidCur-1)]  = OverlapY[CamCur-1+2*(SidCur-1)] + 100*DY/ImageWidth;
				CorrX[CamCur-1+2*(SidCur-1)] = CorrX[CamCur-1+2*(SidCur-1)] + DX;
			}
			ReDraw = true;
		}
		
		// Exit macro
		if(Exit == true)
		{
			SaveDefaultParams = getBoolean("Save current parameters to ScanConfig file?");
			
			// Save tile grid configuration parameters to file
			if(SaveDefaultParams)
			{
				tst = File.exists(RootFolder+"ScanStitch.csv");
				if(tst)SaveDefaultParams = getBoolean("File already exists, overwrite?");
				if(SaveDefaultParams)
				{
					str = "";
					for(s=0;s<=1;s++)
					{
						str = str+d2s(OverlapX[0+2*s],2)+","+d2s(OverlapX[1+2*s],2)+","+d2s(OverlapY[0+2*s],2)+","+d2s(OverlapY[1+2*s],2)+",";
						str = str+d2s(CorrX[0+2*s],0)+","+d2s(CorrX[1+2*s],0)+","+d2s(CorrY[0+2*s],0)+","+d2s(CorrY[1+2*s],0)+",";
						str = str+d2s(CorrZX[0+2*s],0)+","+d2s(CorrZX[1+2*s],0)+","+d2s(CorrZY[0+2*s],0)+","+d2s(CorrZY[1+2*s],0)+",";
						for(c=0;c<8;c++)str = str+d2s(MaxInt[c+8*s],0)+",";
						str = str+d2s(CAMAng[s],4)+","+d2s(CAMSca[s],4)+","+d2s(CAMXCor[s],0)+","+d2s(CAMYCor[s],0);
						if(DualSide)
						{
							str = str+","+d2s(RLXCor[s],2)+","+d2s(RLYCor[s],0)+","+d2s(RLZCor[s],0)+","+d2s(CropFracWidth,4);	
						}
						if(s==0)str = str+",";
					}
					if(FreeZxyCorr)
					{
						str = str+"\n";
						for(i=0;i<lengthOf(ZManOffs);i++)
						{
							if(i>0)str = str + ",";
							str=str+d2s(ZManOffs[i],0);
						}
					}
					File.saveString(str, RootFolder+"ScanStitch.csv");
				}
			}

			// Cleanup
			run("Close All");
			setPasteMode("Copy");
			if(isOpen("ROI Manager"))
			{
				selectWindow("ROI Manager");
				run("Close");
			}
			exit;
		}
		
		// Color mode has been updated, clear board
		if(ColorMode!=OldColorMode)
		{
			selectImage(BoardID);
			run("Select All");
			run("Clear");
			run("Select None");
		}

		// Tile grid exportation
		if(ExportStack == true)
		{
			// Exportation dialog box
			SideMarginsBuf = SideMargins;ZCurBuf = ZCur;CCurBuf = CCur;CamCurBuf = CamCur;
			Dialog.create("Export stack");
			Dialog.addSlider("XdMin", XMin, XMax, XdMin);
			Dialog.addSlider("XdMax", XMin, XMax, XdMax);
			Dialog.addSlider("YdMin", YMin, YMax, YdMin);
			Dialog.addSlider("YdMax", YMin, YMax, YdMax);
			Dialog.addNumber("First slice", ZMin);
			Dialog.addNumber("CAM Z slice switch", ZCur);
			Dialog.addNumber("Last slice", ZMax);
			Dialog.addCheckbox("CAM2 low Z, CAM1 high Z", true);
			Dialog.addCheckbox("Use auto CAM switch", false);
			Dialog.addCheckbox("Convert to 8-bit", false);
			Dialog.addCheckbox("Export all channels", false);
			Dialog.addCheckbox("Do not crop image", false);
			Dialog.addNumber("Sampling factor", 1);
			Dialog.addCheckbox("Perform operation", true);
			Dialog.show();
			XdMin = Dialog.getNumber();
			XdMax = Dialog.getNumber();
			YdMin = Dialog.getNumber();
			YdMax = Dialog.getNumber();
			ZStart = Dialog.getNumber();
			ZSwitch = Dialog.getNumber();
			ZEnd = Dialog.getNumber();
			CAMOrder = Dialog.getCheckbox();
			CAMAuto = Dialog.getCheckbox(); 
			Convert = Dialog.getCheckbox();
			AllChans = Dialog.getCheckbox();
			NoCrop = Dialog.getCheckbox();
			Samp = Dialog.getNumber();
			Apply = Dialog.getCheckbox();
			
			// Perform exportation			
			if(Apply)
			{
				
			// Initialization
			VolumeName = split(RootFolder,"/\\");
			VolumeName = VolumeName[lengthOf(VolumeName)-1];
			SaveVirtualFolder = getDirectory("Set Export Directory");
			
			// This part is similar to what is done in live mode
			run("Select None");
			setBatchMode(true);
			StitchModeCopy = StitchMode;
			if(StitchModeCopy=="Ramp")StitchModeCopy = "Add";
			setPasteMode(StitchModeCopy);
			if(AllChans == true)
			{
				CStart = 0;
				CEnd = CMax;
			}
			else
			{
				CStart = CCur;
				CEnd = CCur;
			}

			// Create Ramp Mask
			if(StitchMode=="Ramp")BlendMask(ImageWidth,OverlapX[CamCur-1]/100,OverlapY[CamCur-1]/100);

			// Create blank image for slice by slice exportation
			if(Convert == true) newImage("Slice", "8-bit black", ImageWidth*(XMax-XMin+1)*(ShowDual+1)+2*SideMargins, ImageHeight*(YMax-YMin+1)+2*SideMargins, 1);
			else newImage("Slice", "16-bit black", ImageWidth*(XMax-XMin+1)*(ShowDual+1)+2*SideMargins, ImageHeight*(YMax-YMin+1)+2*SideMargins, 1);

			// Loop over channels and slices
			ComputeBB = 1;BBStartX = 1/0;BBStartY = 1/0;BBEndX = 0;BBEndY = 0;
			for(CCur=CStart;CCur<=CEnd;CCur++)
			{
			for(ZCur=ZStart;ZCur<=ZEnd;ZCur++)
			{	
				if(CAMAuto == true)
				{
					if(CAMOrder == 1)
					{
						if(ZCur > ZSwitch)CamCur = 1;
						else CamCur = 2;
					}
					else
					{
						if(ZCur < ZSwitch)CamCur = 1;
						else CamCur = 2;
					}
				}
				CropWidth = round(ImageWidth*(100-OverlapX[CamCur-1+2*(SidCur-1)])/100);
				CropHeight = round(ImageHeight*(100-OverlapY[CamCur-1+2*(SidCur-1)])/100);
				showProgress((ZCur-ZStart)/(ZEnd-ZStart));
				selectImage("Slice");
				run("Select All");
				run("Clear", "slice");
				run("Select None");
				
				// Additional loop for dual side mode
				SidMin=SidCur;SidMax=SidCur;
				if(ShowDual==true)
				{
					SidMin = 1;
					SidMax = 2;	
				}
				
				// Paste all images from grid
				for(SidCur2=SidMin;SidCur2<=SidMax;SidCur2++)
				{
				for(j=YdMin;j<=YdMax;j++)
				{
					for(i=XdMin;i<=XdMax;i++)
					{
						// Update filename
						ImageName = replace(FileNameTemplate, XString+IJ.pad(XMin,XDigits), XString+IJ.pad(i,XDigits));
						ImageName = replace(ImageName, YString+IJ.pad(YMin,YDigits), YString+IJ.pad(j,YDigits));
						ImageName = replace(ImageName, RLString+IJ.pad(0,RLDigits), RLString+IJ.pad(SidCur2-1,RLDigits));
						if(FreeZxyCorr)ZCorrected = ZCur+RLZCor[CamCur-1]*(SidCur2-1)+ZManOffs[j+i*(YMax+1-YMin)+(SidCur2-1)*(YMax+1-YMin)*(XMax+1-XMin)]+RLZCor[CamCur-1]*(SidCur2-1);  // Manual ZOffs
						else ZCorrected = ZCur+CorrZX[CamCur-1+2*(SidCur2-1)]*i+CorrZY[CamCur-1+2*(SidCur2-1)]*j+RLZCor[CamCur-1]*(SidCur2-1); // Linear ZOffs
						if(FolderMode)
						{
							ImageName = replace(ImageName, ChanStr[0], ChanStr[CCur]);
							ImageName = replace(ImageName, CAMString+"1", CAMString+d2s(CamCur,0));
							ImageName = replace(ImageName, ZString+IJ.pad(ZMin,ZDigits), ZString+IJ.pad(ZCorrected,ZDigits));
							FolderName = replace(FolderNameTemplate, XString+IJ.pad(XMin,XDigits), XString+IJ.pad(i,XDigits));
							FolderName = replace(FolderName, YString+IJ.pad(YMin,YDigits), YString+IJ.pad(j,YDigits));
							FolderName = replace(FolderName, CString+IJ.pad(0,CDigits), CString+IJ.pad(CCur,CDigits));
							FolderName = replace(FolderName, RLString+IJ.pad(0,RLDigits), RLString+IJ.pad(SidCur2-1,RLDigits));
							if(File.exists(RootFolder+FolderName+ImageName))open(RootFolder+FolderName+ImageName);
							else newImage("Black", "16-bit black", ImageWidth, ImageHeight, 1);
						}
						else
						{
							ImageName = replace(ImageName, CString+IJ.pad(0,CDigits), CString+IJ.pad(CCur,CDigits));
							if((ZCorrected>0)&&(ZCorrected<ZMax)&&File.exists(RootFolder+ImageName))open(RootFolder+ImageName,1+ZCorrected+ZMax*(CamCur-1)*DualCAM);
							else newImage("Black", "16-bit black", ImageWidth, ImageHeight, 1);
						}			
						if((DualSide)&&(MaxInt[CCur+8]/MaxInt[CCur]!=1)&&(SidCur2==2))run("Multiply...", "value="+d2s(MaxInt[CCur]/MaxInt[CCur+8],4));
						if(StitchMode=="Ramp")
						{
							rename("Img");
							run("32-bit");
							imageCalculator("Multiply","Img","Mask");
							setMinAndMax(0,65535);
							run("16-bit");
						}
						if(CamCur == 2)run("Flip Horizontally");
						if((DualSide)&&(CropFracWidth!=0))
						{
							if((i==XdMax)&&(SidCur2==1))
							{
								makeRectangle(ImageWidth-round(ImageWidth*CropFracWidth),0,ImageWidth,ImageHeight);
								run("Clear", "slice");
								run("Select None");
							}
							if((i==XdMin)&&(SidCur2==2))
							{
								makeRectangle(0,0,round(ImageWidth*CropFracWidth),ImageHeight);
								run("Clear", "slice");
								run("Select None");
							}
						}			
						if(DualSide)setMinAndMax(0,MaxInt[CCur]);
						else setMinAndMax(0,MaxInt[CCur+8*(SidCur2-1)]);
						if(Convert == true)run("8-bit");
						run("Copy");
						close();	
						selectImage("Slice");
						if(ShowDual==true)makeRectangle(CropWidth*(i-XMin)-CorrX[CamCur-1+2*(SidCur2-1)]*j+SideMargins+RLXCor[CamCur-1]*(SidCur2-1),CropHeight*(j-YMin)-CorrY[CamCur-1+2*(SidCur2-1)]*i+SideMargins+RLYCor[CamCur-1]*(SidCur2-1),ImageWidth,ImageHeight);
						else makeRectangle(CropWidth*(i-XMin)-CorrX[CamCur-1+2*(SidCur2-1)]*j+SideMargins,CropHeight*(j-YMin)-CorrY[CamCur-1+2*(SidCur2-1)]*i+SideMargins,ImageWidth,ImageHeight);
						if(ComputeBB == 1) // Compute bounding box for CAM1 (same used for CAM2 if cropping is enabled)
						{
							CXs = CropWidth*(i-XMin)-CorrX[2*(SidCur2-1)]*j+SideMargins;
							CXe = CXs + ImageWidth*(ShowDual+1);
							CYs = CropHeight*(j-YMin)-CorrY[2*(SidCur2-1)]*i+SideMargins;
							CYe = CYs + ImageHeight;
							if(CXs < BBStartX)BBStartX = CXs;
							if(CYs < BBStartY)BBStartY = CYs;
							if(CXe > BBEndX)BBEndX = CXe;
							if(CYe > BBEndY)BBEndY = CYe;
						}
						run("Paste");
					}
				}
				}
				ComputeBB = 0;
				run("Select None");
				if((CamCur==2)&&(CAMAng[SidCur-1]!=0))run("Rotate... ", "angle="+d2s(CAMAng[SidCur-1],2)+" grid=1 interpolation=None");
				if((CamCur==2)&&(CAMSca[SidCur-1]!=1))run("Scale...", "x="+d2s(CAMSca[SidCur-1],4)+" y="+d2s(CAMSca[SidCur-1],4)+" interpolation=Bilinear average");
				if((CamCur==2)&&((CAMXCor[SidCur-1]!=0)||(CAMYCor[SidCur-1]!=0)))run("Translate...", "x="+d2s(CAMXCor[SidCur-1],0)+" y="+d2s(CAMYCor[SidCur-1],0)+" interpolation=None");
				if(NoCrop==false)
				{
					makeRectangle(BBStartX,BBStartY,BBEndX-BBStartX+1,BBEndY-BBStartY+1);
					run("Duplicate...", "title=Copy");
					CopyID = getImageID();
				}
				if(Samp != 1)
				{
					run("Scale...", "x="+d2s(Samp,4)+" y="+d2s(Samp,4)+" interpolation=Bilinear average create title=Scaled");
					ScaleID = getImageID();
				}
				if(ShowDual==true)
				{
					if(ZCur>=0)save(SaveVirtualFolder+VolumeName+"_SRL_Z"+IJ.pad(ZCur,4)+"_C"+IJ.pad(CCur,CDigits)+".tif");
					else save(SaveVirtualFolder+VolumeName+"_SRL_Z_"+IJ.pad(abs(ZCur),3)+"_C"+IJ.pad(CCur,CDigits)+".tif");
				}
				else 
				{
					if(ZCur>=0)save(SaveVirtualFolder+VolumeName+"_S"+IJ.pad(SidCur-1,RLDigits)+"_Z"+IJ.pad(ZCur,ZDigits)+"_C"+IJ.pad(CCur,CDigits)+".tif");
					else save(SaveVirtualFolder+VolumeName+"_S"+IJ.pad(SidCur-1,RLDigits)+"_Z_"+IJ.pad(ZCur,ZDigits-1)+"_C"+IJ.pad(CCur,CDigits)+".tif");
				}
				if(NoCrop==false)
				{
					selectImage(CopyID);
					close();
				}
				else rename("Slice");
				if(Samp != 1)
				{
					selectImage(ScaleID);
					close();
				}
				run("Select None");
			}			
			}
			ZCur = ZCurBuf;CCur = CCurBuf;SideMargins = SideMarginsBuf;CamCur = CamCurBuf;
			if(isOpen("Slice"))
			{
				selectImage("Slice");
				close();
			}
			if(StitchMode=="Ramp")
			{
				selectImage("Mask");
				close();
				selectImage(BoardID);
			}
			setBatchMode("exit & display");
			}
		}
		}
	}
}

// Function used to create the ramp intensity mask for smooth blending
function BlendMask(ImgSize,OvlX,OvlY)
{
	newImage("MaskDS", "32-bit black", 256, 256, 1);
	makeRectangle(round(256*OvlX*0.5), round(256*OvlY*0.5), round(256*(1-OvlX)), round(256*(1-OvlY)));
	run("Set...", "value=1");
	run("Select None");
	run("Mean", "block_radius_x="+d2s(0.95*OvlX*256*0.5,0)+" block_radius_y="+d2s(0.95*OvlY*256*0.5,0));
	run("Scale...", "x=- y=- width="+d2s(ImgSize,0)+" height="+d2s(ImgSize,0)+" interpolation=Bilinear average create title=Mask");
	selectImage("MaskDS");
	close();
}