//+------------------------------------------------------------------+
//|                                    news_screenshoter_updated.mq5 |
//|                                      Copyright 2024, Farid Zarie |
//|                                        https://github.com/Far-1d |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Farid Zarie"
#property link      "https://github.com/Far-1d"
#property version   "1.20"


// --- object names
#define BOX_NAME     "info_box"
#define HLINE_NAME   "seperator_line"

//--- ff cal names
#define INAME     "FFC"
#define TITLE		0
#define COUNTRY	1
#define DATE		2
#define TIME		3
#define IMPACT		4
#define FORECAST	5
#define PREVIOUS	6
#define TIMER     "timer_label"
#define LAST_NEWS "last_news_line"
#define UPCOMING  "upcoming_news_line"

// 10 slots for news titles
string TEXT_NAMES[11] = { "info_text0", "info_text1", "info_text2", "info_text3", "info_text4", "info_text5", "info_text6", "info_text7", "info_text8", "info_text9", "info_text10"};


//--- to download the xml
#import "urlmon.dll"
int URLDownloadToFileW(int pCaller,string szURL,string szFileName,int dwReserved,int Callback);
#import

//--- enums
enum playback_speed {
   fast,
   normal,
   slow
};

enum impact_mtds{
   sum,
   indivitual
};


//--- inputs
input group "<<==  Strategy Config  ==>>";
input impact_mtds       impact_mtd        = sum;               // Impact Filter Method
input string            impact            = "3";               // Impact Filter (format for indivitual: L,M,H) (0=disable)
input string            currencies        = "USD,EUR";         // Currency Filter (format for multiple: c1,c2,c3)(empty=disable)
input string            title             = "";                // Title Filter (format for multiple: t1~t2~t3)(empty=disable)
input bool              exact_match       = false;             // Each News Match all Filters ?
input int               trigger           = 30;                // Seconds before news to alert

input group "<<==  FFC Config  ==>>";
input bool              AllowUpdates      = true;              // Allow updates
input int               UpdateHour        = 4;                 // Update every (in hours)

input color             line_clr1      = clrGold;              // Last News Line Color
input color             line_clr2      = clrPaleTurquoise;     // Upcoming News Line Color
input color             box_clr        = clrDarkSlateGray;     // Box Color
input color             text_clr       = clrWhite;             // Text Color

//--- globals
int g_nCandleIndex = -1;            // For Crossover Candle Index
int matched_news[];                 // index of matched news
int matched_news_with_title[];      // index of matched news that pass all filters(including title)
int news_total;
int indexes_impact[];
int indexes_title[];
int indexes_currency[];
string last_message;
datetime last_message_time1 = D'2024.06.01';
datetime last_message_time2 = D'2024.06.01';

string xmlFileName;
string sData;
datetime xmlModifed;
int TimeOfDay;
datetime Midnight;
string Event[200][7];
string EventRearranged[][7];
string last_period;
datetime global_upcoming_time;
datetime global_last_news_time;



//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   global_upcoming_time=D'1970.01.01'; 
   global_last_news_time=D'1970.01.01';
   last_period="";
   //--- check for DLL
   if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
   {
      Alert(INAME+": Please Allow DLL Imports!");
      return(INIT_FAILED);
   }
     
   TimeOfDay=(int)TimeLocal()%86400;
   Midnight=TimeLocal()-TimeOfDay;
   //--- set xml file name ffcal_week_this (fixed name)
   xmlFileName=INAME+"-ffcal_week_this.xml";
//--- checks the existence of the file.
   if(!FileIsExist(xmlFileName))
     {
      xmlDownload();
      xmlRead();
     }
//--- else just read it 
   else xmlRead();
//--- get last modification time
   xmlModifed=(datetime)FileGetInteger(xmlFileName,FILE_MODIFY_DATE,false);
//--- check for updates
   if(AllowUpdates)
     {
      if(xmlModifed<TimeLocal()-(UpdateHour*3600))
        {
         Print(INAME+": xml file is out of date");
         xmlUpdate();
        }
      //--- set timer to update old xml file every x hours  
      else EventSetTimer(UpdateHour*3600);
     }
     
   parseNews();
   rearrangeEventArray();

//--- create timer
   EventSetTimer(1);
   
//---
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  clear_objects();
//--- destroy timer
   EventKillTimer();
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static int total = iBars(_Symbol, PERIOD_CURRENT);
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   if (total != bars)
   {
      parseNews();
      rearrangeEventArray();
      
      total = bars;
   }
   
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---

   if (AllowUpdates)
   {
      if (TimeCurrent() > xmlModifed + UpdateHour*PeriodSeconds(PERIOD_H1))
      {
         xmlUpdate();
      }
   }

   //--- find latest matched news index ✓
   int last_news_index = -1;
   datetime last_news_time;
   int matched_news_last = 0;
   for (int i=ArraySize(EventRearranged)/7 -1; i>=0; i--){
      if (iTime(_Symbol, PERIOD_CURRENT, 0) >= StringToTime(EventRearranged[i][0]+" "+EventRearranged[i][1]))
      { 
         check_filters(i, 0, EventRearranged, false);
         if (ArraySize(matched_news))
         {
            string message = "found latest matched news at "+EventRearranged[i][0]+" "+EventRearranged[i][1];
            if ((int)(TimeCurrent()-last_message_time1) >30)
            {
               last_message_time1 = TimeCurrent();
               Print(message);
            }
            last_news_index = i;
            last_news_time = StringToTime(EventRearranged[i][0]+" "+EventRearranged[i][1]);
            matched_news_last = ArraySize(matched_news);
            break;
         }
      }
   }
   
   //--- find first upcoming news index
   int upcoming_index = -1;
   datetime upcoming_time;
   int matched_news_upcoming = 0;
   for (int i=0; i<ArraySize(EventRearranged)/7; i++)
   {
      if (iTime(_Symbol, PERIOD_CURRENT, 0) < StringToTime(EventRearranged[i][0]+" "+EventRearranged[i][1]))
      {
         check_filters(i, 0, EventRearranged);
         if(ArraySize(matched_news))
         {
            string message = "found a matched upcoming news at "+ EventRearranged[i][0]+" "+EventRearranged[i][1];
            if ((int)(TimeCurrent()-last_message_time2) >30)
            {
               last_message_time2 = TimeCurrent();
               Print(message);
            }
            upcoming_index = i;
            upcoming_time = StringToTime(EventRearranged[i][0]+" "+EventRearranged[i][1]);
            matched_news_upcoming = ArraySize(matched_news);
            break;
         }
      }
   }
   
   if (upcoming_index != -1)
   {
      if (last_period != GetCurrentTimeframe() || global_upcoming_time != upcoming_time)
      {
         draw_timer(last_news_index, upcoming_index);
         last_period = GetCurrentTimeframe();
         global_upcoming_time = upcoming_time;
         
         create_objects(matched_news_last, matched_news_upcoming);
         string text = "";
         check_filters(upcoming_index, 0, EventRearranged); // need to refresh matched_news
         for (int j=0;j<matched_news_upcoming; j++){
            StringConcatenate(text, "currency: ", EventRearranged[matched_news[j]][2], "  impact : ", EventRearranged[matched_news[j]][3], "  title : ", EventRearranged[matched_news[j]][4]);
            ObjectSetString(0, TEXT_NAMES[j], OBJPROP_TEXT, text);
            ObjectSetInteger(0, TEXT_NAMES[j], OBJPROP_COLOR, line_clr2);
         }
         
      }
      //--- change last news data to default (useful when drawing next time an input changes)
      if (last_news_index == -1)
      {
         global_last_news_time = D'1970.01.01';
      }
      
      //--- Timer and Trigger
      int seconds_to_trigger = -1;
      string diff_time = time_difference(TimeCurrent(), StringToTime(EventRearranged[upcoming_index][0]+" "+EventRearranged[upcoming_index][1]), seconds_to_trigger);
      ObjectSetString(0, TIMER, OBJPROP_TEXT, diff_time+" until next news");
      Comment(diff_time+" until next news");
      
      static bool triggered = false;
      if (seconds_to_trigger < trigger && ! triggered)
      {
         trigger_action();
         triggered = true;
      }
      else if(seconds_to_trigger > trigger && triggered)
      {
         triggered = false;
      }
   }
   else // no upcoming news
   {
      ObjectSetString(0, TIMER, OBJPROP_TEXT, "no upcoming news");
      if (last_news_index == -1)
         Print("no old and upcoming news matched criteria");
   }
   
   if (last_news_index != -1)
   {
      if (global_last_news_time != last_news_time || last_period != GetCurrentTimeframe())
      {
         draw_timer(last_news_index, upcoming_index);
         global_last_news_time = last_news_time;
         last_period = GetCurrentTimeframe();
         if (upcoming_index == -1)
         {  
            create_objects(matched_news_last, matched_news_upcoming);
            //--- change upcoming news data to default (useful when drawing next time an input changes)
            global_upcoming_time = D'1970.01.01';
         }
      }
      check_filters(last_news_index, 0, EventRearranged, false); // need to refresh matched_news
      string text = "";
      for (int j=0;j<matched_news_last; j++){
         StringConcatenate(text, "currency: ", EventRearranged[matched_news[j]][2], "  impact : ", EventRearranged[matched_news[j]][3], "  title : ", EventRearranged[matched_news[j]][4]);
         ObjectSetString(0, TEXT_NAMES[j+matched_news_upcoming], OBJPROP_TEXT, text);
         ObjectSetInteger(0, TEXT_NAMES[j+matched_news_upcoming], OBJPROP_COLOR, line_clr1);
      }
   }
}
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| save the xml data in an array                                    |
//+------------------------------------------------------------------+
void parseNews(){
   //--- define the XML Tags, Vars
   string sTags[7]={"<title>","<country>","<date><![CDATA[","<time><![CDATA[","<impact><![CDATA[","<forecast><![CDATA[","<previous><![CDATA["};
   string eTags[7]={"</title>","</country>","]]></date>","]]></time>","]]></impact>","]]></forecast>","]]></previous>"};
   int index=0;
   int next=-1;
   int BoEvent=0,begin=0,end=0;
   string myEvent="";

//--- split the currencies into the two parts 
   string MainSymbol=StringSubstr(Symbol(),0,3);
   string SecondSymbol=StringSubstr(Symbol(),3,3);
//--- loop to get the data from xml tags
   //Print("sData ", sData);
   while(true)
     {
      BoEvent=StringFind(sData,"<event>",BoEvent);
      if(BoEvent==-1) break;
      BoEvent+=7;
      next=StringFind(sData,"</event>",BoEvent);
      if(next == -1) break;
      myEvent = StringSubstr(sData,BoEvent,next-BoEvent);
      //Print("myEvent ", myEvent);
      
      BoEvent = next;
      begin=0;
      for(int i=0; i<7; i++)
        {
         Event[index][i]="";
         next=StringFind(myEvent,sTags[i],begin);
         //--- Within this event, if tag not found, then it must be missing; skip it
         if(next==-1) continue;
         else
           {
            //--- We must have found the sTag okay...
            //--- Advance past the start tag
            begin=next+StringLen(sTags[i]);
            end=StringFind(myEvent,eTags[i],begin);
            //---Find start of end tag and Get data between start and end tag
            if(end>begin && end!=-1)
               Event[index][i]=StringSubstr(myEvent,begin,end-begin);
           }
        }
      //--- sometimes they forget to remove the tags :)
      if(StringFind(Event[index][TITLE],"<![CDATA[")!=-1)
         StringReplace(Event[index][TITLE],"<![CDATA[","");
      if(StringFind(Event[index][TITLE],"]]>")!=-1)
         StringReplace(Event[index][TITLE],"]]>","");
      if(StringFind(Event[index][TITLE],"]]>")!=-1)
         StringReplace(Event[index][TITLE],"]]>","");
      //---
      if(StringFind(Event[index][FORECAST],"&lt;")!=-1)
         StringReplace(Event[index][FORECAST],"&lt;","");
      if(StringFind(Event[index][PREVIOUS],"&lt;")!=-1)
         StringReplace(Event[index][PREVIOUS],"&lt;","");

      //--- set some values (dashes) if empty
      if(Event[index][FORECAST]=="") Event[index][FORECAST]="---";
      if(Event[index][PREVIOUS]=="") Event[index][PREVIOUS]="---";
      
      //EventMinute=int(EventTime-TimeGMT())/60;

      index++;
     }
}


//+------------------------------------------------------------------+
//| rearange the parsed data into desired format                     |
//+------------------------------------------------------------------+
void rearrangeEventArray(){
   ArrayResize(EventRearranged, 0);
   for (int i=0; i<200; i++){
      if (Event[i][0] == NULL) break;
      
      ArrayResize(EventRearranged, i+1);
      
      string broker_time = ConvertGMTtoBrokerTime(reformDate(Event[i][2])+" "+ConvertTo24Hour(Event[i][3]));
      int pos = StringFind(broker_time, " ");
      
      EventRearranged[i][0] = StringSubstr(broker_time, 0, pos);     // Date
      EventRearranged[i][1] = StringSubstr(broker_time, pos + 1);    // Time
      EventRearranged[i][2] = Event[i][1]; // Symbol
      EventRearranged[i][3] = Event[i][4]; // Impact
      EventRearranged[i][4] = Event[i][0]; // Title
      EventRearranged[i][5] = Event[i][5]; // Not important
      EventRearranged[i][6] = Event[i][6]; // Not important
   }

}

//+-------------------------------------------------------------------------------------------+
//| Download XML file from forexfactory                                                       |
//| for windows 7 and later file path would be:                                               |           
//| C:\Users\xxx\AppData\Roaming\MetaQuotes\Terminal\xxxxxxxxxxxxxxx\MQL5\Files\xmlFileName   |
//+-------------------------------------------------------------------------------------------+
void xmlDownload()
  {
//---
   ResetLastError();
   string sUrl="https://nfs.faireconomy.media/ff_calendar_thisweek.xml";     //updated 2021.03.24 https://www.forexfactory.com/thread/post/13459190#post13459190 - обновил
   //string FilePath=StringConcatenate(TerminalInfoString(TERMINAL_DATA_PATH),"\\MQL4\\files\\",xmlFileName);
   //string FilePath=TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\files\\" + xmlFileName;
   
   //int FileGet=URLDownloadToFileW(NULL,sUrl,FilePath,0,NULL);
   string headers;
   char post[], result[];
   int timeout = 10000;
   int res = WebRequest("GET", sUrl, "", timeout, post, result, headers);
   if (res == 200)
   {
      int h = FileOpen(xmlFileName, FILE_WRITE | FILE_BIN, "", CP_UTF8);
      if (h == INVALID_HANDLE) Print("data downloaded but couldn't save it to file");
      else {
         FileWriteArray(h,result,0,ArraySize(result)); 
         //--- Closing the file 
         FileClose(h); 
      }
   }
   
   //if(FileGet==0) PrintFormat(INAME+": %s file downloaded successfully!",xmlFileName);
//--- check for errors   
   else PrintFormat(INAME+": failed to download %s file, Error code = %d",xmlFileName,GetLastError());
//---
  }
  
//+------------------------------------------------------------------+
//| Read the XML file                                                |
//+------------------------------------------------------------------+
void xmlRead()
  {
//---
   uchar uCharA[];
   ResetLastError();
   int FileHandle=FileOpen(xmlFileName,FILE_BIN|FILE_READ);
   if(FileHandle!=INVALID_HANDLE)
     {
      FileReadArray(FileHandle, uCharA);

      sData = CharArrayToString(uCharA, 0);
     
      //--- close
      FileClose(FileHandle);
     }
//--- check for errors   
   else PrintFormat(INAME+": failed to open %s file, Error code = %d",xmlFileName,GetLastError());
//---
  }
  
//+------------------------------------------------------------------+
//| Check for update XML                                             |
//+------------------------------------------------------------------+
void xmlUpdate()
  {
//--- do not download on saturday
   MqlDateTime tm;
   TimeToStruct(Midnight,tm);   
   if(tm.day_of_week==6) return;
   else
     {
      Print(INAME+": check for updates...");
      Print(INAME+": delete old file");
      FileDelete(xmlFileName);
      xmlDownload();
      xmlRead();
      xmlModifed=(datetime)FileGetInteger(xmlFileName,FILE_MODIFY_DATE,false);
      PrintFormat(INAME+": updated successfully! last modified: %s",(string)xmlModifed);
     }
//---
  }

//+------------------------------------------------------------------+
//| Converts ff date into yyyy.mm.dd - by deVries                    |
//+------------------------------------------------------------------+
string reformDate(string strDate)
  {
//---
   int n1stDash=StringFind(strDate, "-");
   int n2ndDash=StringFind(strDate, "-", n1stDash+1);

   string strMonth=StringSubstr(strDate,0,2);
   string strDay=StringSubstr(strDate,3,2);
   string strYear=StringSubstr(strDate,6,4);

   return(strYear + "." + strMonth + "." + strDay);
//---
  }

//+------------------------------------------------------------------+
//| Converts ff time into hh:mm - by deVries                         |
//+------------------------------------------------------------------+
string ConvertTo24Hour(string strTime)
  {
//---
   int nTimeColonPos=StringFind(strTime,":");
   string strHour=StringSubstr(strTime,0,nTimeColonPos);
   string strMinute=StringSubstr(strTime,nTimeColonPos+1,2);
   string strAM_PM=StringSubstr(strTime,StringLen(strTime)-2);

   int nHour24=( int )StringToInteger(strHour);
   if((strAM_PM=="pm" || strAM_PM=="PM") && nHour24!=12) nHour24+=12;
   if((strAM_PM=="am" || strAM_PM=="AM") && nHour24==12) nHour24=0;
   string strHourPad="";
   if(nHour24<10) strHourPad="0";

   return(strHourPad + IntegerToString(nHour24) + ":" + strMinute);
//---
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string time_difference(datetime start, datetime end, int& seconds_to_trigger){
   int diff_seconds = (int)(end - start);
   seconds_to_trigger = diff_seconds;
   int hours = diff_seconds / 3600;
   int minutes = (diff_seconds - hours * 3600) / 60;
   int seconds = diff_seconds - hours * 3600 - minutes * 60;
   string diff_time = StringFormat("%02d:%02d:%02d", hours, minutes, seconds);
   
   return diff_time;
}


//+------------------------------------------------------------------+
//| GMT datetime string to Broker time (+3:00)                       |
//+------------------------------------------------------------------+
string ConvertGMTtoBrokerTime(string gmt_datetime) {
   datetime gmt_time = StringToTime(gmt_datetime);
   datetime broker_time = gmt_time + 3 * 3600;
   return TimeToString(broker_time);
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetCurrentTimeframe() {
   int timeframe = Period();
   string timeframe_str;
   
   switch(timeframe) {
      case PERIOD_M1:
         timeframe_str = "M1";
         break;
      case PERIOD_M5:
         timeframe_str = "M5";
         break;
      case PERIOD_M15:
         timeframe_str = "M15";
         break;
      case PERIOD_M30:
         timeframe_str = "M30";
         break;
      case PERIOD_H1:
         timeframe_str = "H1";
         break;
      case PERIOD_H4:
         timeframe_str = "H4";
         break;
      case PERIOD_D1:
         timeframe_str = "D1";
         break;
      case PERIOD_W1:
         timeframe_str = "W1";
         break;
      case PERIOD_MN1:
         timeframe_str = "MN1";
         break;
      default:
         timeframe_str = "Unknown";
         break;
   }
   
   return timeframe_str;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void draw_timer(int last_index, int upcoming_index){
   ObjectCreate(0, TIMER, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, TIMER, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, TIMER, OBJPROP_XDISTANCE, 200);
   ObjectSetInteger(0, TIMER, OBJPROP_YDISTANCE, 50);
   ObjectSetInteger(0, TIMER, OBJPROP_COLOR, text_clr);
   if (last_index != -1)
   {
      ObjectCreate(0, LAST_NEWS, OBJ_VLINE, 0, StringToTime(EventRearranged[last_index][0]+" "+EventRearranged[last_index][1]), 0);
      ObjectSetInteger(0, LAST_NEWS, OBJPROP_COLOR, line_clr1);
   }
   if (upcoming_index != -1)
   {
      ObjectCreate(0, UPCOMING, OBJ_VLINE, 0, StringToTime(EventRearranged[upcoming_index][0]+" "+EventRearranged[upcoming_index][1]), 0);
      ObjectSetInteger(0, UPCOMING, OBJPROP_COLOR, line_clr2);
   }
}




//+-------------------------------------------------------------------------------------------------------+




//+------------------------------------------------------------------+
//| check all filter and return result                               |
//+------------------------------------------------------------------+
bool check_filters(int index, int candle, string &array[][], bool forward=true){
   bool 
      vol_filter     = true,
      title_filter   = false,
      impact_filter  = false,
      curr_filter    = false;
   
   ArrayResize(matched_news, 0);
   ArrayResize(matched_news_with_title, 0);
   
   news_total = 0;
   // find total number of news at candle
   int last = 10;
   while (index + last > ArraySize(array)/7){
      last --;
   }
   
   //--- find last index that matches the time of the first upcoming news
   if (last>=1)
   {
      for (int j=1; j<last; j++){
         if (StringToTime(array[index][0]+" "+array[index][1]) < StringToTime(array[index+j][0]+" "+array[index+j][1]))
         {
            last = j;
            break;
         }
      }
   }   
   for (int j=0; j<last; j++){ //maximum 10 news for a candle
   // check next indexs of news array also have the same time
      if (forward)
      {
         if (iTime(_Symbol, PERIOD_CURRENT, candle) < StringToTime(array[index+j][0]+" "+array[index+j][1]))
         {
            news_total ++;
         }
      }
      else
      {
         if (iTime(_Symbol, PERIOD_CURRENT, candle) >= StringToTime(array[index+j][0]+" "+array[index+j][1]))
         {
            news_total ++;
         }
      }
   }

   
   // Impact Check
   impact_filter = check_impact(index, candle, array, last);
   
   // Title Filter
   title_filter = check_title(index, candle, array);
   
   // Currency Filter
   curr_filter = check_currency(index, candle, array);
            
   if (title_filter && impact_filter && curr_filter) 
   {  
      //Print("-----------------------------------");
      //Print("index :", index);
      //Print("impacts : ");
      //ArrayPrint(indexes_impact);
      //Print("curr : ");
      //ArrayPrint(indexes_currency);
      //Print("titles : ");
      //ArrayPrint(indexes_title);
      
      for (int i=0; i<ArraySize(indexes_impact); i++){
         for (int j=0; j<ArraySize(indexes_currency); j++){
            if (indexes_impact[i] == indexes_currency[j])
            {
               int size = ArraySize(matched_news);
               ArrayResize(matched_news, size+1);
               matched_news[size] = indexes_impact[i];
               
               for (int k=0; k<ArraySize(indexes_title); k++){
                  if (indexes_impact[i] == indexes_title[k]) 
                  {
                     int size2 = ArraySize(matched_news_with_title);
                     ArrayResize(matched_news_with_title, size2+1);
                     matched_news_with_title[size2] = indexes_title[k];
                  }
               }
            }
         }
      }
      if (ArraySize(matched_news_with_title) == 0)
      {
         ArrayResize(matched_news, 0);
      }
      if (exact_match)
      {
         if (ArraySize(indexes_impact) != ArraySize(indexes_currency) || ArraySize(indexes_impact) != ArraySize(indexes_title))
         {
            ArrayResize(matched_news, 0);
         }
      }
      return true;
   }
   return false;
}



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool check_impact(int i, int candle, string& array[][], int last){
   int l=0;
   int m=0;
   int h=0;
   ArrayResize(indexes_impact, 0);
   
   for (int j=0; j<last; j++) {    // maximum 10 news per candle

         if (array[i+j][3] == "L" || array[i+j][3] == "Low") l++;
         else if (array[i+j][3] == "M" || array[i+j][3] == "Medium") m++;
         else if (array[i+j][3] == "H" || array[i+j][3] == "High") h++;
         
         // save indexes that are ok with impact
         int size = ArraySize(indexes_impact);
         ArrayResize(indexes_impact, size+1);
         indexes_impact[size] = i+j;

   }
   
   //news_total = l+m+h;
   
   if (impact_mtd == sum)
   {
      if (l+m+h >= StringToInteger(impact)) 
      {
         return true;
      }
   }
   else 
   {
      string impacts[];
      string sep=",";                // A separator as a character 
      ushort u_sep;                  // The code of the separator character 
      u_sep=StringGetCharacter(sep,0); 
      
      int k = StringSplit(impact, u_sep, impacts);
      if (k == 3)
      {
         if ((int)impacts[0] <= l && (int)impacts[1] <= m && (int)impacts[2] <= h ){
            return true;
         }
      }
   }
   
   if (impact == "0")
   {
      return true;
   }
   // since impact filter did not pass, no index is returned
   ArrayResize(indexes_impact, 0);
   
   return false;
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool check_title(int i, int candle, string& array[][]){
   string titles[];
   string sep="~";                // A separator as a character 
   ushort u_sep;                  // The code of the separator character 
   u_sep=StringGetCharacter(sep,0); 
   
   int k = StringSplit(title, u_sep, titles);
   
   bool flag = false;
   ArrayResize(indexes_title, 0); 
   for(int j=0; j<news_total; j++){
      if (k!=0)
      {
         for (int x=0; x<k; x++){
            if (StringFind(array[i+j][4], titles[x]) != -1)
            {
               int size = ArraySize(indexes_title);
               ArrayResize(indexes_title, size+1);
               indexes_title[size] = i+j;
               flag = true;
            }
         }
      }
      else
      {
         int size = ArraySize(indexes_title);
         ArrayResize(indexes_title, size+1);
         indexes_title[size] = i+j;
         flag = true;
      }
   }
   
   if (title == "") 
   {   
      return true;
   }
   if (!flag) ArrayResize(indexes_title, 0);
   return flag;
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool check_currency(int i, int  candle, string& array[][]){
   string curr_array[];
   string sep=",";                // A separator as a character 
   ushort u_sep;                  // The code of the separator character 
   u_sep=StringGetCharacter(sep,0); 
   
   int k = StringSplit(currencies, u_sep, curr_array);
   
   bool flag = false;
   ArrayResize(indexes_currency, 0);

   for(int j=0; j<news_total; j++){
      for (int x=0; x<k; x++){
         if (StringFind(array[i+j][2], curr_array[x]) != -1)
         {
            int size = ArraySize(indexes_currency);
            ArrayResize(indexes_currency, size+1);
            indexes_currency[size] = i+j;
            flag = true;
         }
      }
   }
   
   if (currencies == "") 
   {
      return true;
   }
   if (!flag) ArrayResize(indexes_currency, 0);
   return flag;
}



//+------------------------------------------------------------------+
//| draw related objects on chart                                    |
//+------------------------------------------------------------------+
void create_objects(int old_news, int new_news){
   int lines = old_news + new_news;
   ObjectCreate(0, BOX_NAME, OBJ_RECTANGLE_LABEL, 0, 0,0);
   ObjectSetInteger(0, BOX_NAME, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, BOX_NAME, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, BOX_NAME, OBJPROP_YDISTANCE, (lines)*26 + 5);
   ObjectSetInteger(0, BOX_NAME, OBJPROP_XSIZE, 450);
   ObjectSetInteger(0, BOX_NAME, OBJPROP_YSIZE, (lines+1)*26);
   ObjectSetInteger(0, BOX_NAME, OBJPROP_BGCOLOR, box_clr);
   ObjectSetInteger(0, BOX_NAME, OBJPROP_COLOR, box_clr);
   
   for(int i=0; i<lines; i++){
      ObjectCreate(0, TEXT_NAMES[i], OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, TEXT_NAMES[i], OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, TEXT_NAMES[i], OBJPROP_XDISTANCE, 30);
      ObjectSetInteger(0, TEXT_NAMES[i], OBJPROP_YDISTANCE, (i+1)*26);
   }
      
   ObjectCreate(0, HLINE_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, HLINE_NAME, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, HLINE_NAME, OBJPROP_XDISTANCE, 30);
   ObjectSetInteger(0, HLINE_NAME, OBJPROP_YDISTANCE, new_news*26+5);
   ObjectSetInteger(0, HLINE_NAME, OBJPROP_XSIZE, 430);
   ObjectSetInteger(0, HLINE_NAME, OBJPROP_YSIZE, 3);
   ObjectSetInteger(0, HLINE_NAME, OBJPROP_COLOR, text_clr);
   ObjectSetInteger(0, HLINE_NAME, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, HLINE_NAME, OBJPROP_WIDTH, 0);
}



//+------------------------------------------------------------------+
//| remove all objects drawn                                         |
//+------------------------------------------------------------------+
void clear_objects(){
   ObjectDelete(0, BOX_NAME);
   ObjectDelete(0, HLINE_NAME);
   ObjectDelete(0, TIMER);
   ObjectDelete(0, LAST_NEWS);
   ObjectDelete(0, UPCOMING);
   for (int i=0; i<10; i++)
      ObjectDelete(0, TEXT_NAMES[i]);
}


//+------------------------------------------------------------------+
//| any action needed                                                |
//+------------------------------------------------------------------+
void trigger_action(){
   Print("Trigger Activated");
}