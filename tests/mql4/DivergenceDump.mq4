//+------------------------------------------------------------------+
//|                                               DivergenceDump.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test EA (not shipped): dumps the MT4 Divergence Signal Alerts    |
//| buffers and checks repainting in the Strategy Tester (Dump4.mqh).|
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

#define DUMP4_BUFFERS "0,1,2,3,4,5"
#define DUMP4_PROBE   "0,1"
#define DUMP4_LIVE                     // the indicator scans only its last InpHistory bars

input bool InpMACD     = true;
input bool InpHidden   = false;
input int  InpLeft     = 5;
input int  InpRight    = 3;
input int  InpMaxDist  = 60;
input bool InpClean    = true;
input bool InpBoth     = false;
input int  InpHistory  = 2000;

double IndValue(const int buf,const int shift)
  {
   return(iCustom(NULL,0,"Divergence\\DivergenceSignalAlerts",true,14,InpMACD,12,26,9,true,InpHidden,InpLeft,InpRight,
                  5,InpMaxDist,InpClean,InpBoth,InpHistory,false,C'38,166,98',C'226,74,70',0.3,
                  false,false,"alert.wav",false,false,buf,shift));
  }

#include <IndTest4/Dump4.mqh>
//+------------------------------------------------------------------+
