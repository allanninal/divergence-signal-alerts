//+------------------------------------------------------------------+
//|                                       DivergenceSignalAlerts.mq5 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Free indicator: RSI and MACD divergences on one chart. Draws a   |
//| line between the two price pivots and an arrow on the bar where  |
//| the divergence became known (the pivot needs `right` closed bars |
//| after it), so nothing is ever drawn into the past or removed.    |
//| Regular and hidden divergences; alerts on the newest closed bar. |
//| Engine: Include/Divergence/Div.mqh.                              |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link      "https://www.allanninal.dev/mql5"
#property version   "1.00"
#property description "RSI and MACD divergence on the chart: regular and hidden, line between the pivots, arrow on the confirming bar."
#property description "Closed bars only: an arrow never moves or disappears. Alerts: pop-up, sound, push, e-mail."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6
#property indicator_label1  "Bullish divergence"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  C'38,166,98'
#property indicator_width1  2
#property indicator_label2  "Bearish divergence"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  C'226,74,70'
#property indicator_width2  2
#property indicator_label3  "Bullish type (1 regular, 2 hidden)"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Bearish type (1 regular, 2 hidden)"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "RSI"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "MACD histogram"
#property indicator_type6   DRAW_NONE

#include <Divergence/Div.mqh>

input group "Oscillators"
input bool   InpRSI       = true;    // RSI divergence
input int    InpRSIPeriod = 14;      // RSI period
input bool   InpMACD      = true;    // MACD histogram divergence
input int    InpFast      = 12;      // MACD fast EMA
input int    InpSlow      = 26;      // MACD slow EMA
input int    InpSignal    = 9;       // MACD signal EMA
input group "Divergence"
input bool   InpRegular   = true;    // Regular divergence (reversal)
input bool   InpHidden    = false;   // Hidden divergence (continuation)
input int    InpLeft      = 5;       // Pivot: bars on the left
input int    InpRight     = 3;       // Pivot: bars on the right (the confirmation delay)
input int    InpMinDist   = 5;       // Pivots at least this many bars apart
input int    InpMaxDist   = 60;      // Pivots at most this many bars apart
input bool   InpClean     = true;    // Clean lines: no bar crosses the line between the pivots
input bool   InpBoth      = false;   // Only when RSI and MACD both diverge
input group "Display"
input int    InpHistory   = 2000;    // Closed bars to scan on the chart (100-20000)
input bool   InpLines     = true;    // Draw the line between the price pivots
input color  InpColBull   = C'38,166,98';   // Bullish colour
input color  InpColBear   = C'226,74,70';   // Bearish colour

#include <Divergence/SignalAlerts.mqh>

const string PRODUCT="Divergence Signal Alerts";
const string PREFIX ="DVSA_";

double   g_bull[],g_bear[],g_tbull[],g_tbear[],g_rsi[],g_macd[];
DVParams g_p;
DVState  g_s;
int      g_start=0;                        // chart bar of engine bar 0
int      g_fed=0;                          // chart bars fed so far (the next to feed is g_start+g_fed)
datetime g_alert_bar=0;

void Clear()
  {
   ObjectsDeleteAll(0,PREFIX);
   DVInit(g_s);
   g_fed=0;
  }

void DrawLine(const datetime t1,const double p1,const datetime t2,const double p2,const int dir,const int type)
  {
   string name=PREFIX+IntegerToString((long)t2)+(dir>0 ? "b" : "s");
   if(ObjectFind(0,name)>=0)
      return;
   ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,dir>0 ? InpColBull : InpColBear);
   ObjectSetInteger(0,name,OBJPROP_STYLE,type==1 ? STYLE_SOLID : STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,type==1 ? 2 : 1);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,StringFormat("%s %s divergence (%s)",type==1 ? "Regular" : "Hidden",
                   dir>0 ? "bullish" : "bearish",DVMaskNames(g_s.ev_mask)));
  }

int OnInit()
  {
   if(!InpRSI && !InpMACD)
     {
      Print(PRODUCT,": switch on RSI, MACD or both");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(!InpRegular && !InpHidden)
     {
      Print(PRODUCT,": switch on regular, hidden or both");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRSIPeriod<2 || InpFast<1 || InpSlow<=InpFast || InpSignal<1 || InpLeft<1 || InpRight<1 ||
      InpMinDist<1 || InpMaxDist<InpMinDist || InpLeft+InpRight+InpMaxDist>=DV_N || InpHistory<100 || InpHistory>20000)
     {
      Print(PRODUCT,StringFormat(": check the periods; pivot bars + max distance must stay below %d; history 100-20000",DV_N));
      return(INIT_PARAMETERS_INCORRECT);
     }
   ZeroMemory(g_p);
   g_p.use[DV_RSI]=InpRSI;
   g_p.use[DV_MACD]=InpMACD;
   g_p.rsi_n=InpRSIPeriod;
   g_p.macd_fast=InpFast; g_p.macd_slow=InpSlow; g_p.macd_sig=InpSignal;
   g_p.left=InpLeft; g_p.right=InpRight; g_p.min_dist=InpMinDist; g_p.max_dist=InpMaxDist;
   g_p.regular=InpRegular; g_p.hidden=InpHidden; g_p.clean=InpClean;
   g_p.min_count=(InpBoth && InpRSI && InpMACD ? 2 : 1);
   SetIndexBuffer(0,g_bull,INDICATOR_DATA);
   SetIndexBuffer(1,g_bear,INDICATOR_DATA);
   SetIndexBuffer(2,g_tbull,INDICATOR_DATA);
   SetIndexBuffer(3,g_tbear,INDICATOR_DATA);
   SetIndexBuffer(4,g_rsi,INDICATOR_DATA);
   SetIndexBuffer(5,g_macd,INDICATOR_DATA);
   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,14);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,-14);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpColBull);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpColBear);
   for(int i=0; i<6; i++)
      PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"Divergence Signal Alerts");
   Clear();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,PREFIX);
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<InpLeft+InpRight+3)
      return(0);
   ArraySetAsSeries(time,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);
   if(prev_calculated==0)                          // first run or the history changed: start again
     {
      Clear();
      g_start=MathMax(0,rates_total-1-InpHistory);
      ArrayInitialize(g_bull,EMPTY_VALUE);
      ArrayInitialize(g_bear,EMPTY_VALUE);
      ArrayInitialize(g_tbull,EMPTY_VALUE);
      ArrayInitialize(g_tbear,EMPTY_VALUE);
      ArrayInitialize(g_rsi,EMPTY_VALUE);
      ArrayInitialize(g_macd,EMPTY_VALUE);
     }
   else
      for(int i=MathMax(prev_calculated-1,0); i<rates_total; i++)
        {
         g_bull[i]=EMPTY_VALUE; g_bear[i]=EMPTY_VALUE; g_tbull[i]=EMPTY_VALUE; g_tbear[i]=EMPTY_VALUE;
         if(i>=g_start+g_fed)
           { g_rsi[i]=EMPTY_VALUE; g_macd[i]=EMPTY_VALUE; }
        }
   bool live=(prev_calculated>0);
   string events="";
//--- feed every closed bar not fed yet (the forming bar rates_total-1 never)
   for(int i=g_start+g_fed; i<=rates_total-2; i++)
     {
      bool ev=DVFeed(g_s,g_p,high[i],low[i],close[i]);
      g_fed++;
      g_rsi[i]=DVOsc(g_s,DV_RSI,g_s.cnt-1);
      g_macd[i]=DVOsc(g_s,DV_MACD,g_s.cnt-1);
      if(!ev)
         continue;
      int pi=g_start+g_s.ev_p,qi=g_start+g_s.ev_q;
      if(g_s.ev_dir>0)
        {
         g_bull[i]=low[i];
         g_tbull[i]=g_s.ev_type;
        }
      else
        {
         g_bear[i]=high[i];
         g_tbear[i]=g_s.ev_type;
        }
      if(InpLines)
         DrawLine(time[qi],g_s.ev_qpx,time[pi],g_s.ev_ppx,g_s.ev_dir,g_s.ev_type);
      if(live && i==rates_total-2 && time[i]>g_alert_bar)
        {
         g_alert_bar=time[i];
         events=StringFormat("%s %s divergence (%s) on %s %s",g_s.ev_type==1 ? "Regular" : "Hidden",
                             g_s.ev_dir>0 ? "bullish" : "bearish",DVMaskNames(g_s.ev_mask),_Symbol,
                             StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7));
        }
     }
   if(events!="")
      SignalAlertMessage(PRODUCT,events);
   return(rates_total);
  }
//+------------------------------------------------------------------+
