//+------------------------------------------------------------------+
//|                                                          Div.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Divergence engine, one CLOSED bar per step (no repaint), used by |
//| Divergence Signal Alerts.                                        |
//|                                                                  |
//| Pivots on price: a pivot low at bar p has a low below each of    |
//| the `left` bars before it and not above any of the `right` bars  |
//| after it, so it is known `right` bars later (the confirmation    |
//| bar). Pivot highs mirror it.                                     |
//| At a new pivot low p, the previous pivot lows q (nearest first,  |
//| up to 3, `min_dist`..`max_dist` bars back) are tried:            |
//|   regular bullish: low[p] < low[q] and oscillator[p] > osc[q];   |
//|   hidden bullish:  low[p] > low[q] and oscillator[p] < osc[q].   |
//| Bearish mirrors it on pivot highs. With "clean lines" on, no bar |
//| between q and p may cross the straight line q-p, on price or on  |
//| that oscillator. The first q where at least `min_count`          |
//| oscillators diverge is the result; `mask` says which ones.       |
//|                                                                  |
//| Oscillators (textbook formulas, tested against tests/reference.py):|
//|   RSI   Wilder, close                                            |
//|   MACD  histogram = EMA(fast) - EMA(slow) - EMA(signal) of that  |
//| EMAs and RMAs are seeded with the SMA of their first n values.   |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef DIV_MQH
#define DIV_MQH

#define DV_N     160                  // ring of recent bars (max_dist + left + right must stay below it)
#define DV_OSC   2
#define DV_RSI   0
#define DV_MACD  1
#define DV_PIV   4                    // previous pivots remembered per side

//--- EMA seeded with the SMA of the first n values
struct DVEma
  {
   int    cnt;
   double sum;
   double v;
  };
void DVEmaInit(DVEma &s) { s.cnt=0; s.sum=0.0; s.v=EMPTY_VALUE; }
double DVEmaStep(DVEma &s,const int n,const double x)
  {
   s.cnt++;
   if(s.cnt<n)
     { s.sum+=x; s.v=EMPTY_VALUE; }
   else
      if(s.cnt==n)
        { s.sum+=x; s.v=s.sum/n; }
      else
         s.v=s.v+2.0/(n+1)*(x-s.v);
   return(s.v);
  }

struct DVParams
  {
   bool   use[DV_OSC];
   int    rsi_n;
   int    macd_fast,macd_slow,macd_sig;
   int    left,right,min_dist,max_dist;
   bool   regular,hidden;
   bool   clean;                      // no bar may cross the q-p line, on price or the oscillator
   int    min_count;                  // oscillators that must agree
  };

struct DVState
  {
   int    cnt;                        // bars fed; bar k is the k-th fed bar (0-based)
   double hi[DV_N],lo[DV_N];
   double osc[DV_OSC*DV_N];           // osc[o*DV_N + k%DV_N]
   //--- RSI (Wilder)
   double prev_close,rsi_sg,rsi_sl,rsi_gain,rsi_loss;
   //--- MACD
   DVEma  ef,es,esg;
   //--- previous pivots: absolute bar numbers, newest first
   int    pl[DV_PIV],ph[DV_PIV];
   int    npl,nph;
   //--- the event the last fed bar confirmed
   int    ev_dir;                     // +1 bullish, -1 bearish, 0 none
   int    ev_type;                    // 1 regular, 2 hidden
   int    ev_mask;                    // bit o set = oscillator o diverged
   int    ev_count;
   int    ev_p,ev_q;                  // pivot bars (absolute), newer and older
   double ev_ppx,ev_qpx;              // their prices (low for bullish, high for bearish)
  };

int DVi(const int k) { return(k%DV_N); }
double DVOsc(const DVState &s,const int o,const int k) { return(s.osc[o*DV_N+DVi(k)]); }

void DVInit(DVState &s)
  {
   s.cnt=0;
   ArrayInitialize(s.hi,0);
   ArrayInitialize(s.lo,0);
   ArrayInitialize(s.osc,EMPTY_VALUE);
   s.prev_close=0; s.rsi_sg=0; s.rsi_sl=0; s.rsi_gain=0; s.rsi_loss=0;
   DVEmaInit(s.ef); DVEmaInit(s.es); DVEmaInit(s.esg);
   s.npl=0; s.nph=0;
   for(int i=0; i<DV_PIV; i++)
     { s.pl[i]=-1; s.ph[i]=-1; }
   s.ev_dir=0; s.ev_type=0; s.ev_mask=0; s.ev_count=0; s.ev_p=-1; s.ev_q=-1; s.ev_ppx=0; s.ev_qpx=0;
  }

//--- the oscillators on the new bar k
void DVOscStep(DVState &s,const DVParams &p,const int k,const double c)
  {
   int r=DVi(k);
   for(int o=0; o<DV_OSC; o++)
      s.osc[o*DV_N+r]=EMPTY_VALUE;
//--- RSI (Wilder)
   if(k>=1)
     {
      double ch=c-s.prev_close,g=MathMax(ch,0.0),ls=MathMax(-ch,0.0);
      int n=p.rsi_n;
      if(k<n)
        { s.rsi_sg+=g; s.rsi_sl+=ls; }
      else
         if(k==n)
           { s.rsi_sg+=g; s.rsi_sl+=ls; s.rsi_gain=s.rsi_sg/n; s.rsi_loss=s.rsi_sl/n; }
         else
           { s.rsi_gain=(s.rsi_gain*(n-1)+g)/n; s.rsi_loss=(s.rsi_loss*(n-1)+ls)/n; }
      if(k>=n)
         s.osc[DV_RSI*DV_N+r]=(s.rsi_loss==0.0 ? 100.0 : (s.rsi_gain==0.0 ? 0.0 : 100.0-100.0/(1.0+s.rsi_gain/s.rsi_loss)));
     }
//--- MACD histogram
   double ef=DVEmaStep(s.ef,p.macd_fast,c),es=DVEmaStep(s.es,p.macd_slow,c);
   if(ef!=EMPTY_VALUE && es!=EMPTY_VALUE)
     {
      double m=ef-es,sg=DVEmaStep(s.esg,p.macd_sig,m);
      if(sg!=EMPTY_VALUE)
         s.osc[DV_MACD*DV_N+r]=m-sg;
     }
   s.prev_close=c;
  }

//--- is bar p (absolute) a pivot low / high, judged on the bars up to k = p + right?
bool DVPivotLow(const DVState &s,const DVParams &pr,const int p)
  {
   if(p-pr.left<0)
      return(false);
   double v=s.lo[DVi(p)];
   for(int j=1; j<=pr.left; j++)
      if(!(v<s.lo[DVi(p-j)]))
         return(false);
   for(int j=1; j<=pr.right; j++)
      if(v>s.lo[DVi(p+j)])
         return(false);
   return(true);
  }
bool DVPivotHigh(const DVState &s,const DVParams &pr,const int p)
  {
   if(p-pr.left<0)
      return(false);
   double v=s.hi[DVi(p)];
   for(int j=1; j<=pr.left; j++)
      if(!(v>s.hi[DVi(p-j)]))
         return(false);
   for(int j=1; j<=pr.right; j++)
      if(v<s.hi[DVi(p+j)])
         return(false);
   return(true);
  }

//--- no bar strictly between q and p crosses the straight line q-p: below it for lows (bull), above it for highs (bear)
bool DVClean(const DVState &s,const int o,const int q,const int p,const int dir)
  {
   double a=(o<0 ? (dir>0 ? s.lo[DVi(q)] : s.hi[DVi(q)]) : DVOsc(s,o,q));
   double b=(o<0 ? (dir>0 ? s.lo[DVi(p)] : s.hi[DVi(p)]) : DVOsc(s,o,p));
   for(int j=q+1; j<p; j++)
     {
      double line=a+(b-a)*(j-q)/(double)(p-q);
      double v=(o<0 ? (dir>0 ? s.lo[DVi(j)] : s.hi[DVi(j)]) : DVOsc(s,o,j));
      if(v==EMPTY_VALUE)
         return(false);
      if(dir>0 ? v<line : v>line)
         return(false);
     }
   return(true);
  }

//--- divergences at the new pivot p (dir +1 low, -1 high); fills ev_*
void DVCheck(DVState &s,const DVParams &pr,const int p,const int dir)
  {
   int n=(dir>0 ? s.npl : s.nph);
   for(int i=0; i<n; i++)
     {
      int q=(dir>0 ? s.pl[i] : s.ph[i]);
      int d=p-q;
      if(d<pr.min_dist)
         continue;
      if(d>pr.max_dist)
         break;                                   // newest first: the rest are older still
      double pp=(dir>0 ? s.lo[DVi(p)] : s.hi[DVi(p)]),pq=(dir>0 ? s.lo[DVi(q)] : s.hi[DVi(q)]);
      int type=0;
      if(dir>0)
         type=(pp<pq ? 1 : (pp>pq ? 2 : 0));
      else
         type=(pp>pq ? 1 : (pp<pq ? 2 : 0));
      if(type==0 || (type==1 && !pr.regular) || (type==2 && !pr.hidden))
         continue;
      if(pr.clean && !DVClean(s,-1,q,p,dir))
         continue;
      int mask=0,cnt=0;
      for(int o=0; o<DV_OSC; o++)
        {
         if(!pr.use[o])
            continue;
         double op=DVOsc(s,o,p),oq=DVOsc(s,o,q);
         if(op==EMPTY_VALUE || oq==EMPTY_VALUE)
            continue;
         //--- regular bull: osc higher low; hidden bull: osc lower low; bear mirrors (sign flip)
         bool div=(type==1 ? dir*(op-oq)>0 : dir*(op-oq)<0);
         if(!div)
            continue;
         if(pr.clean && !DVClean(s,o,q,p,dir))
            continue;
         mask|=(1<<o);
         cnt++;
        }
      if(cnt>=MathMax(1,pr.min_count))
        {
         s.ev_dir=dir; s.ev_type=type; s.ev_mask=mask; s.ev_count=cnt;
         s.ev_p=p; s.ev_q=q; s.ev_ppx=pp; s.ev_qpx=pq;
         return;
        }
     }
  }

void DVRemember(int &arr[],int &n,const int p)
  {
   for(int i=DV_PIV-1; i>0; i--)
      arr[i]=arr[i-1];
   arr[0]=p;
   n=MathMin(n+1,DV_PIV);
  }

//--- feed one CLOSED bar; true when it confirmed a divergence (ev_*)
bool DVFeed(DVState &s,const DVParams &pr,const double h,const double l,const double c)
  {
   int k=s.cnt;
   s.hi[DVi(k)]=h;
   s.lo[DVi(k)]=l;
   DVOscStep(s,pr,k,c);
   s.cnt++;
   s.ev_dir=0; s.ev_type=0; s.ev_mask=0; s.ev_count=0; s.ev_p=-1; s.ev_q=-1;
   int p=k-pr.right;
   if(p<0)
      return(false);
   if(DVPivotLow(s,pr,p))
     {
      DVCheck(s,pr,p,1);
      DVRemember(s.pl,s.npl,p);
     }
   if(s.ev_dir==0 && DVPivotHigh(s,pr,p))
     {
      DVCheck(s,pr,p,-1);
      DVRemember(s.ph,s.nph,p);
     }
   else
      if(s.ev_dir!=0 && DVPivotHigh(s,pr,p))       // a bar can be both; keep the high for later pivots
         DVRemember(s.ph,s.nph,p);
   if(s.ev_dir==0)
      return(false);
   return(true);
  }

string DVOscName(const int o)
  {
   switch(o)
     {
      case DV_RSI:   return("RSI");
      default:       return("MACD");
     }
  }
string DVMaskNames(const int mask)
  {
   string s="";
   for(int o=0; o<DV_OSC; o++)
      if((mask & (1<<o))!=0)
         s+=(s=="" ? "" : "+")+DVOscName(o);
   return(s);
  }

#endif
//+------------------------------------------------------------------+
