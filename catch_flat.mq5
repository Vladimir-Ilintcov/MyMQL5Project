#property strict
#property version "1.0"

enum enum_df
  {
   MT,
   DF
  };

string _DFSymbol ="";
double DF_BID = 0, DF_ASK= 0;

void ReduceDFSpread(double prc)
  {

   double hs = ((DF_ASK-DF_BID)*prc*0.01)/2;
   DF_BID = DF_BID + hs;
   DF_ASK = DF_ASK - hs;
  }
//--- input parameters
input group                "********* DF PARAMETERS ************"
input string DFSymbol = "";
input string DFLogin = "";
input string DFPassword = "";
input int DFPORT = 12350;
input string DFIP = "45.77.159.242";
input double DF_SPREAD_REDUCE_PRC = 0;
input enum_df Type_DF = MT;
input group                "********* Optimisation parametrs ************"
input int                  MinPips = 10;
input int                  PeriodAvg = 5;
input int                  PeriodSize_x = 35;
input double               MultSize_x = 1.8;
input int                  MinWidth = 51;
int                  Delta_H = 0;
int                  Delta_L = 0;
input group               "*** Visualisation options ***"
input bool                 VisualiseOutput = false;
input bool                 CheckMargin = false;
input group                "*********************"

sinput int                 Mag = 5;

double lastTradeResult = 0.0;

datetime sec_sun_mar, last_sun_mar, last_sun_oct, first_sun_nov;

int TimeDaylightCorrections(datetime tc, MqlDateTime& ct)
  {
   int res = 0 ;
   static int year = 0;
   if(ct.year != year)
     {
      year = ct.year;
      MqlDateTime dt;
      dt.year = ct.year;
      dt.mon = 10;
      dt.day = 31;
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      datetime dweek31oct = StructToTime(dt);
      Print(__FUNCTION__, "  ", ct.year,"  ", year);
      TimeToStruct(dweek31oct, dt);
      int dayweek = dt.day_of_week;
      last_sun_oct = dweek31oct - dayweek * 60 * 60 * 24;
      dt.year = ct.year;
      dt.day = 7;
      dt.mon = 11;
      datetime dweek07nov = StructToTime(dt);
      TimeToStruct(dweek07nov, dt);
      dayweek = dt.day_of_week;
      first_sun_nov = dweek07nov - dayweek * 60 * 60 * 24;
      dt.year = ct.year;
      dt.day = 31;
      dt.mon = 3;
      datetime dweek31mar = StructToTime(dt);
      TimeToStruct(dweek31mar, dt);
      dayweek = dt.day_of_week;
      last_sun_mar = dweek31mar - dayweek * 60 * 60 * 24;
      // Print (last_sun_mar);
      //***************************************************************
      dt.year = ct.year;
      dt.day = 14;
      dt.mon = 3;

      datetime dweek14mar = StructToTime(dt);

      TimeToStruct(dweek14mar, dt);
      dayweek = dt.day_of_week;

      sec_sun_mar = dweek14mar - dayweek * 60 * 60 * 24;
      //Print (sec_sun_mar);
      //***************************************************************
     }
   if(tc >= sec_sun_mar && tc <= last_sun_mar)
      res = -1;
   if(tc >= last_sun_oct && tc <= first_sun_nov)
      res = -1;

   return res;
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool tradehour = false;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetDailyChangePercentage()
  {
   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_D1, 0, 2, rates);

   if(copied < 2)
     {
      Print("Insufficient historical data available");
      return 0.0;
     }

   double currentClose = rates[0].close;
   double previousClose = rates[1].close;

   double dailyChange = currentClose - previousClose;
   double dailyChangePercentage = (dailyChange / previousClose) * 100;
   double roundedPercentage = NormalizeDouble(dailyChangePercentage, 2);

   return roundedPercentage;
  }

bool TradeHour(datetime dt, MqlDateTime& timE, int _Starthour, int _Endhour, bool _Trade_on_day = false)

  {
   int sh = 0, eh = 0;

   int hr = timE.hour;

   if(_Starthour >= 24)
      sh = _Starthour % 24;
   else
      sh = _Starthour;
   if(_Endhour > 24 && _Endhour != 24)
      eh = _Endhour % 24;
   else
      eh = _Endhour;

   tradehour = false;
   if(sh > eh && (hr > sh - 1 || hr < eh) && !_Trade_on_day)
      tradehour = true;
   if((sh < eh) && (hr > sh - 1 && hr < eh))
      tradehour = true;
   static bool maxDailyChangeExecuted = false; // Flag to track if Active_MaxDailyChange has been executed
   if(!tradehour)
     {
      maxDailyChangeExecuted = false; // Reset the flag at the end hour

     }

   if(tradehour && Active_MaxDailyChange)
     {

      if(hr == sh && !maxDailyChangeExecuted)
        {

         if(GetDailyChangePercentage() >= MaxDailyChange_Percentage || GetDailyChangePercentage() <= -MaxDailyChange_Percentage)
           {
            Check_MaxDailyChange = false;
            maxDailyChangeExecuted = true; // Set the flag to true to indicate Active_MaxDailyChange has been executed

           }
         else
           {
            Check_MaxDailyChange = true;
           }
        }

     }

   if(Active_MaxDailyChange)
     {
      if(!Check_MaxDailyChange)
        {
         tradehour = false;
        }
     }

   return(tradehour);
  }

bool CheckMarketOpen()
  {
   bool res = false;
   datetime from, to;
   datetime ts = TimeCurrent();
//Print (ts);
   MqlDateTime tz;
   TimeToStruct(ts, tz);

   ENUM_DAY_OF_WEEK dayweek = (ENUM_DAY_OF_WEEK)tz.day_of_week;
   if(SymbolInfoSessionTrade(_Symbol, dayweek, 0, from, to))
     {
      ts %= 24 * 60 * 60;
      if(ts > to)
         SymbolInfoSessionTrade(_Symbol, dayweek, 1, from, to);

      if(ts >= from && ts <= to)
         return true;

     }

   return res;
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|Основной класс старегии                                           |
//+------------------------------------------------------------------+

#define BARSi 10000
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class EMA
  {
public:

   double            Value1;
   int               period;
   double            Alpha;
   string            sym;

                     EMA() {};


   void              EMASet(string _sym, int _period)
     {
      sym = _sym;
      period = _period;
      Value1 = EMPTY_VALUE;
      Alpha = 1.0 / period;
     }
                    ~EMA(void)   {};

   double            GetEMA(double NewValue)
     {
      if(Value1 == EMPTY_VALUE)
        {
         Value1 =  NewValue;
        }

      Value1 += (NewValue - Value1) * Alpha;

      //Print (Alpha,"    ",period,"   ",st5((NewValue - Value1) * Alpha));

      return(Value1);
     }

   string            st5(double _x)
     {
      return DoubleToString(_x, 5);
     }

  };

class Fletcher
  {

private:
   double            Avg;
   double            Size_x;
   bool              Calc;
   double            xu ;
   double            ask;
   double            bid;
   double            Value1 ;
   double            Valuew ;
   bool              fr;
   int               inPeriodAvg ;
   int               inPeriodSize_x ;
   double            inMultSize_x;
   double            MinWidth;
   double            DeltaH;
   double            DeltaL;
   double            PrevMinMax1;
   int               digits;

   int               inMinPips ;
   datetime          cur_time;
   long              last_time;

   bool              FlagUP ;
   double            MinMax;
   bool              Real;
   int               icount ;
   long              last_time1;
   bool              flag_correct;
   datetime               timecorr;

   EMA               Ema;
   EMA               Emw;

public:
   string            sym ;
   double            point;
   double            h;
   double            l;

                     Fletcher() {};

                    ~Fletcher()
     {
      sym = "";
      h = -EMPTY_VALUE;
      l = EMPTY_VALUE;
      return;
     };

                     Fletcher(string _sym, int _inMinPips, int _inPeriodAvg = 0, int _inPeriodSize_x = 0, double _inMultSize_x = 0, int _MinWidth = 0, int _DeltaH = 0, int _DeltaL = 0)
     {

      if(MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
         Real = false;
      else
         Real = true;

      bool is_custom = false;
      if(!SymbolExist(_sym, is_custom))
        {
         sym = "";
        }


      SymbolSelect(_sym, true);
      sym = _sym;

      // Print ("EA_   ", _LastError);


      digits = (int) SymbolInfoInteger(sym, SYMBOL_DIGITS);
      point = SymbolInfoDouble(sym, SYMBOL_POINT);
      MqlTick t;
      SymbolInfoTick(sym, t);

      if(Type_DF == MT)
        {
         ask = t.ask;
         bid = t.bid;
        }
      else
        {}
        
      Avg = bid;
      Size_x = point;
      MinMax = EMPTY_VALUE;

      Value1  = bid;
      Valuew = 15 * point;
      h = ask;
      l = bid;
      Avg = bid;
      Size_x = point;
      PrevMinMax1 = EMPTY_VALUE;


      inMinPips = _inMinPips;
      inPeriodAvg = _inPeriodAvg;
      inPeriodSize_x = _inPeriodSize_x;
      inMultSize_x = _inMultSize_x;
      MinWidth = _MinWidth;
      DeltaH = _DeltaH ;
      DeltaL = _DeltaL ;

      long lt = iTime(sym, PERIOD_M1, BARSi);
      last_time = lt * 1000;
      Print("   Start from  ", TimeToString(lt));

      Ema.EMASet(sym, inPeriodAvg);
      Emw.EMASet(sym, inPeriodSize_x);
      icount = 0;

      int handle = iMA(sym, PERIOD_M1, 1, 0, MODE_EMA, PRICE_CLOSE);

      flag_correct = true;

     }

   bool              ZZLast(double & PrevMinMax, double _ask, double _bid);
   void              CalcCH(double _ask, double _bid);
   string            st5(double _x);
   void              Run();
   void              Correct();
  };

bool   Fletcher::           ZZLast(double &PrevMinMax, double _ask, double _bid)

  {
   bool Res = false;

   if(MinMax == EMPTY_VALUE)
      MinMax = _bid;
   if(PrevMinMax == EMPTY_VALUE)
      PrevMinMax = _ask;

   if(FlagUP)
     {
      if(_bid >= MinMax)
         MinMax = _bid;
      else
         if(Res = (MinMax - _ask >= inMinPips * point))
           {
            PrevMinMax = MinMax;
            MinMax = _ask;
            FlagUP = false;
           }
     }
   else
     {
      if(_ask <= MinMax)
         MinMax = _ask;
      else
         if(Res = (_bid - MinMax >= inMinPips * point))
           {
            PrevMinMax = MinMax;
            MinMax = _bid;
            FlagUP = true;
           }
     }

   return(Res);
  }


void Fletcher::   Run()
  {

   if(TimeCurrent() > timecorr + 600  && Real)
     {
      timecorr = TimeCurrent();
      Correct();
     }

   MqlTick Ticks[];

   ResetLastError();
   datetime curr_time = TimeCurrent();
   int count = CopyTicksRange(sym, Ticks,  COPY_TICKS_INFO, last_time);

//Print("Count --------------------------- ",count);
//Print("last_time --------------------------- ",last_time);


   if(_LastError > 0)
      Print(sym,"   ",_LastError);
   ResetLastError();


   if(count > 0)
     {
      last_time = Ticks[count - 1].time * 1000 + 1000;
      for(int i = 0; i < count; i++)
        {
         CalcCH(Ticks[i].ask, Ticks[i].bid);

        }
     }

   if(count > 100)
      Print(sym, " Fletcher  ", count, "   ", (datetime)(last_time / 1000));

  }

void Fletcher::   CalcCH(double _ask, double _bid)
  {
   ask = _ask;
   bid = _bid;

   if(ZZLast(xu, ask, bid))
     {
      icount++;

      Avg = Ema.GetEMA(xu);
      Size_x = Emw.GetEMA(MathAbs(xu - Avg));


      double h0 = Avg + Size_x;
      double l0 = Avg - Size_x;

      double center0 = (h0 + l0) / 2.0;
      double w0 = (h0 - l0) / 2.0 * inMultSize_x;

      h = center0 + w0 + DeltaH * point;
      l = center0 - w0 - DeltaL * point;



      double xwidth = h - l ;
      double center = (h + l) * 0.5;
      if(xwidth < MinWidth * point)
        {
         h = center + MinWidth / 2.0 * point;
         l = center - MinWidth / 2.0 * point;
        }

      h = NormalizeDouble(h, digits);
      l = NormalizeDouble(l, digits);
     }

//Print ((int)((h-l)/point));

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string Fletcher:: st5(double _x)
  {
   return DoubleToString(_x, 5);
  }
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Fletcher::Correct()
  {
   if(sym == "")
     {
      sym = "";
      h = EMPTY_VALUE;
      l = -EMPTY_VALUE;

      return ;
     }



   MqlTick Ticks[];

   ResetLastError();
   last_time1 = iTime(sym, PERIOD_M1, BARSi);
   int count = CopyTicksRange(sym, Ticks,  COPY_TICKS_INFO, last_time1 * 1000, 0);
   if(_LastError > 0)
      Print(_LastError);
   ResetLastError();


   if(count > 0)
     {
      for(int i = 0; i < count; i++)
        {
         CalcCH(Ticks[i].ask, Ticks[i].bid);
        }
     }



  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+

#include <Trade\\Trade.mqh>
CTrade trade;
#include <Trade\\AccountInfo.mqh>
CAccountInfo acc;
#include <Trade\\HistoryOrderInfo.mqh>
CHistoryOrderInfo his;
#include <Trade\\Positioninfo.mqh>
CPositionInfo poS;
#include <Trade\\OrderInfo.mqh>
COrderInfo ord;
#include <Trade\\DealInfo.mqh>
CDealInfo deal;
#include<Trade\\TerminalInfo.mqh>
CTerminalInfo ter;
// MQL4&5-Code

// Изящное и шустрое сравнение double-значений "цены": CP(Price1) == Price2, CP(Price1) >= Price2 и т.д.
// Возможно задание точности double-сравнений: CP(Lots1, 0.01) == Lots2, CP(Lots1, 0.1) >= Lots2 и т.д.

#define EPSILON (1.0e-7 + 1.0e-13)
#define HALF_PLUS  (0.5 + EPSILON)
#define HALF_MINUS (0.5 - EPSILON)

#define DEFINE_COMPARE_OPERATOR(OPERATOR)                                      \
  bool operator OPERATOR( const double dPrice ) const                          \
  {                                                                            \
    const double Tmp = (PRICE_COMPARE::Price - dPrice) / PRICE_COMPARE::point; \
                                                                               \
    return((int)((Tmp > 0) ? Tmp + HALF_MINUS : Tmp - HALF_PLUS) OPERATOR 0);  \
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class PRICE_COMPARE
  {
private:
   static double     Price;
   static double     point;

public:
   static const PRICE_COMPARE* Compare(const double dPrice, const double dPoint = 0)
     {
      PRICE_COMPARE::point = (dPoint == 0) ? ::Point() : dPoint;
      PRICE_COMPARE::Price = dPrice;

      // https://www.mql5.com/ru/forum/1111/page1671#comment_2759248
      return(#ifdef __MQL5__ &TempPriceCompare #else #ifdef _DEBUG &TempPriceCompare #else
                   NULL #endif #endif);
     }

                     DEFINE_COMPARE_OPERATOR(==)
                     DEFINE_COMPARE_OPERATOR(!=)
                     DEFINE_COMPARE_OPERATOR(>=)
                     DEFINE_COMPARE_OPERATOR(<=)
                     DEFINE_COMPARE_OPERATOR(>)
                     DEFINE_COMPARE_OPERATOR(<)

   static double     MyNormalizeDouble(const double Value, const int digits)
     {
      // Добавление static ускоряет код в три раза!
      static const double Points[] = {1.0e-0, 1.0e-1, 1.0e-2, 1.0e-3, 1.0e-4, 1.0e-5, 1.0e-6, 1.0e-7, 1.0e-8};

      return((int)((Value > 0) ? Value / Points[digits] + HALF_PLUS : Value / Points[digits] - HALF_PLUS) * Points[digits]);
     }
  };

static double PRICE_COMPARE::Price = 0;
static double PRICE_COMPARE::point = 0;

#undef DEFINE_COMPARE_OPERATOR
#undef HALF_MINUS
#undef HALF_PLUS
#undef EPSILON

// Compare Prices
const PRICE_COMPARE* CP(const double dPrice, const double dPoint = 0)
  {
   return(PRICE_COMPARE::Compare(dPrice, dPoint));
  }

// https://www.mql5.com/ru/forum/1111/page1671#comment_2759248
#ifdef __MQL5__
static const PRICE_COMPARE TempPriceCompare;
#else
#ifdef _DEBUG
static const PRICE_COMPARE TempPriceCompare;
#endif
#endif

// Почти в четыре раза быстрее соответствующей стандартной функции (build 1395)
// #define NormalizeDouble PRICE_COMPARE::MyNormalizeDouble
#define NormalizeDouble PRICE_COMPARE::MyNormalizeDouble


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
enum trade_T
  {
   MARKET,
   LIMIT
  };

enum enum_filling_Mode
  {
   IOC,
   FOK

  };

input trade_T        Trade_type = LIMIT;
input enum_filling_Mode Filling_Type = IOC;
sinput bool          prnlog = false;//Печать отладочных логов


int                  EndTradeFriday = 26;
int                  StartHourTradeMonday = -100;

int                  RollOverHour = -1;
int                  EHourClose = -119;//Заккрытие всех сделок в , часов
input bool           Tradeonday = false;


input group                "******  Money_M  ******";
input double         Lot = 0.0;//Фиксированный лот
double               Risk = 0.1; //Риск на один канал
double               MinBallance = -1;
input group                "******  Time_M";
int                  ExtraMinuteClose = -5;
input bool           RollOverTrade = true;


bool SL_Buy = false;
bool SL_Sell = false;


//group                "*******************";


//group                "******  Debag_M";


//
//#include <fxsaber\MultiTester\MTTester.mqh> // https://www.mql5.com/ru/code/26132
//sinput datetime inTesterStartDate = 0; // Конец интервала оптимизации
//sinput datetime inTesterEndDate = 0; // Конец интервала оптимизации
//
////+------------------------------------------------------------------+
////|                                                                  |
////+------------------------------------------------------------------+
//datetime GetTesterEndDate( void )
//{
//   if(MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
//   {
//      string Str;
//      return(MTTESTER::GetSettings(Str) ? (datetime)MTTESTER::GetValue(Str, "ToDate") : 0);
//   }
//   else
//      return 0;
//}
//
////+------------------------------------------------------------------+
////|                                                                  |
////+------------------------------------------------------------------+
//datetime GetTesterStartDate( void )
//{
//   if(MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
//   {
//      string Str;
//      return(MTTESTER::GetSettings(Str) ? (datetime)MTTESTER::GetValue(Str, "FromDate") : 0);
//   }
//   else
//      return 0;
//}
//
////+------------------------------------------------------------------+
////|                                                                  |
////+------------------------------------------------------------------+
//const datetime TesterEndDate = MQLInfoInteger(MQL_OPTIMIZATION) ? inTesterEndDate : GetTesterEndDate();
//const datetime TesterStartDate = MQLInfoInteger(MQL_OPTIMIZATION) ? inTesterStartDate : GetTesterStartDate();
//
////+------------------------------------------------------------------+
////|                                                                  |
////+------------------------------------------------------------------+
//void OnTesterInit( void )
//{
//   ParameterSetRange("inTesterEndDate", false, TesterEndDate, 0, 0, 0);
//   ParameterSetRange("inTesterStartDate", false, TesterStartDate, 0, 0, 0);
//   ChartClose();
//}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTesterDeinit() {}
datetime TIME_MS = TimeLocal() * 1000;

double Price_Open;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class MyTrade
  {

private:

   MqlTradeRequest   r;
   MqlTradeResult    xr;
   double            SLprice_s;
   double            SLprice_b;
   bool              hb, hs ;
   bool              FirstRun;
   double            MINLOT;
   double            LOTSTEP;
   int               MLL;
   double            MAXLOT;
   double            point;
   int               digits;
   int               sl;
   string            sym;
   bool              REAL;
   bool              ob, os, obl, osl;
   int               StartHour;
   int               EndHour;
   int               mag;
   string            com;
   bool              hedge;
   bool              ch_market;
   string            comx;
   double            opprice;

public:

   double            Ask;
   double            Bid;
   double            h;
   double            l;
   bool              tt;

                     MyTrade() {};
                    ~MyTrade()
     {
      sym = "";
      h = EMPTY_VALUE;
      l = -EMPTY_VALUE;
      return;
     };

   void                SetTrade(string _sym, int _Starthour, int _Endhour, int _SL, int _mag, string _com = "")

     {
      StartHour = _Starthour;
      EndHour = _Endhour;

      bool is_custom = false;
      if(!SymbolExist(_sym, is_custom))
        {
         sym = "";
        }

      SymbolSelect(_sym, true);
      sym = _sym;
      mag = _mag;
      sl = _SL;
      ob = os = obl = osl = false ;
      hb = hs = false;
      SLprice_s = EMPTY_VALUE;
      SLprice_s = -EMPTY_VALUE;
      REAL = true;
      MINLOT = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      LOTSTEP  = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      MLL = (int) log10(1 / LOTSTEP);
      MAXLOT  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      trade.SetAsyncMode(false);
      point = SymbolInfoDouble(sym, SYMBOL_POINT);
      digits = (int) SymbolInfoInteger(sym, SYMBOL_DIGITS);
      com = _com;
      comx = com + (string)mag;
      if(acc.MarginMode() == 0)
         hedge = false;
      else
         hedge = true;
      if(MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
         REAL =  false;
     }

   void              Trade(double _h, double _l)
     {
      if(sym.Length() == 0)
        {
         sym = "";
         h = EMPTY_VALUE;
         l = -EMPTY_VALUE;
         return ;
        }

      trade.SetExpertMagicNumber(mag);

      h = _h;
      l = _l;

      datetime dt = TimeCurrent();
      MqlDateTime t1;
      TimeToStruct(dt, t1);

      tt = TradeHour(dt, t1, StartHour, EndHour, Tradeonday) ;

      ch_market = CheckMarketOpen();
      if(Risk < 0)
         tt = false;

      trade.LogLevel(LOG_LEVEL_ERRORS);

      //*****************************************************************
      if(h <= 0 || l <= 0)
         return;
      ///*****************************************************************
      MqlTick t;
      SymbolInfoTick(sym, t);
      Ask = t.ask;
      Bid = t.bid;
      ///*****************************************************************

      if(Trade_type == LIMIT)
        {

         ///*****************************************************************

         CheckOpen(ob, os, obl, osl);

         if((ob || os) && ch_market)
           {
            if(StopLoss(t1))
              {
               hs = false;
               hb = false;
              }
           }

         if(Rollover(t1) && !RollOverTrade)
           {
            DeleteLimit(ORDER_TYPE_BUY_LIMIT);
            DeleteLimit(ORDER_TYPE_SELL_LIMIT);

            for(int i = PositionsTotal() - 1; i >= 0; i--)
              {
               if(poS.SelectByIndex(i))
                 {
                  if(CheckPosition())
                    {
                     if(poS.TakeProfit() != 0)
                        trade.PositionModify(poS.Ticket(), 0, 0);
                     //Print (mag,"   ", Rollover());
                    }
                 }

              }
            return;
           }

         if(!tt && ch_market)
           {
            if(obl)
              {
               if(DeleteLimit(ORDER_TYPE_BUY_LIMIT))
                 {
                  if(prnlog)
                     Print("<---   ", __LINE__, "  ", "3 Dell Buylimit ", tt);
                 }
              }
            if(osl)
              {
               if(DeleteLimit(ORDER_TYPE_SELL_LIMIT))
                 {
                  if(prnlog)
                     Print("<---   ", __LINE__, "  ", "3 Dell Selllimit ", tt);
                 }
              }
           }

         if(ch_market)
            ModifyOrders(h, l);

         if(tt && ch_market)
           {
            double mhBal = 0, mlBal = 0;
            double price = 0;
            if(Bid >= h)
               price = Bid;
            else
               price = h;
            SetNextBallans(price, l, mhBal, mlBal);
            double Drdwsl = 0;
            double lotsSell = GetPosLots(POSITION_TYPE_SELL);
            double lotsBuy = GetPosLots(POSITION_TYPE_BUY);

            double lotsBuyLimit = GetOrdLots(ORDER_TYPE_BUY_LIMIT);
            double lotsSellLimit = GetOrdLots(ORDER_TYPE_SELL_LIMIT);

            double TotlotSell = LotsOptimized(price, ORDER_TYPE_SELL, mhBal);
            double curLotsSell = lotsSell + lotsSellLimit;
            double selllots = TotlotSell - curLotsSell;
            if(!hedge)
               selllots = TotlotSell - curLotsSell + lotsBuy;
            if(prnlog)
               Print("<---  ", __LINE__, " SELL Lots = ", lotsSell, "  ",  lotsSellLimit, "   ", st5(selllots));
            if(selllots >= TotlotSell * 0.05)
              {
               //  Print("<---  ", __LINE__, " SELL Lots = ", lotsSell, " TotlotSell = ",  TotlotSell, " curLotsSell =  ", st5(curLotsSell), "   lotsSellLimit = ", lotsSellLimit,"  mhBal =  " ,mhBal, " mlBal = ", mlBal);
               ResetLastError();

               selllots = Get_DobleLotByMinus(selllots,"Sell_Limit");
               
               if(prnlog)
                 {
                  Print("<---   ", __LINE__, "  ", st5(h), " Open Selllimit 1  ", Bid, "  ", GetLastError());
                 }
               if(OpenSellLimit(selllots, h, l))
                 {
                  if(prnlog)
                     Print("<---   ", __LINE__, "  ", GetLastError(), "  SellLimit   ", selllots);
                  ResetLastError();
                 }

              }
            if(selllots <= -MINLOT)
              {

              }
            if(Ask < l)
               price = Ask;
            else
               price = l;
            SetNextBallans(h, price, mhBal, mlBal);
            double Drdwbl = 0.0;

            double TotlotBuy = LotsOptimized(price, ORDER_TYPE_BUY, mlBal);

            double curLotsBuy = lotsBuy + lotsBuyLimit;
            double buylots = TotlotBuy - curLotsBuy;
            if(!hedge)
               buylots = TotlotBuy - curLotsBuy + lotsSell;
            if(prnlog)
               Print("<---  ", __LINE__, " BUY Lots = ", lotsBuy, "  ",  lotsBuyLimit, "   ", st5(buylots));
            //********************************************************************
            if(buylots >= TotlotBuy * 0.05)
              {
               // Print("<---  ", __LINE__, " BUY Lots = ", lotsBuy, "  ",  lotsBuyLimit, "   ", st5(buylots), "   LotSell = ",lotsSell);
               ResetLastError();
               if(prnlog)
                  Print("<---   ", __LINE__, "  ", st5(l), "  Open Buylimit 1  ", Ask);

               buylots = Get_DobleLotByMinus(buylots,"Buy_Limit");

               if(OpenBuyLimit(buylots, h, l))
                 {
                  if(prnlog)
                     Print("<---   ", __LINE__, "  ", GetLastError(), "  Buylimit  ", buylots);
                  ResetLastError();
                 }

              }
            if(buylots <= -MINLOT)
              {

              }

           }

         //****************************************************************
        }

      if(Trade_type == MARKET)
        {

         if(Rollover(t1) && !RollOverTrade)
            return;

         CheckOpen(ob, os);

         if(ob || os)
           {
            if(StopLoss(t1))
              {
               hs = false;
               hb = false;
              }
           }

         static double BID_Price;
         static double ASK_Price;

         if(Type_DF == DF)
           {

            BID_Price = DF_BID;
            ASK_Price = DF_ASK;

           }
         else
            if(Type_DF == MT)
              {

               BID_Price = Bid;
               ASK_Price = Ask;

              }

         if(VisualiseOutput)
           {
            DrawLine("_h",_h);
            DrawLine("_l",_l);

           }

         if(Type_Trade_How == Trail_TakeProfit)
           {

            if(tt)
              {

               if(BID_Price >= _h && Market_Last_Order != "Sell" && !SL_Sell)
                 {

                  OpenSell();

                 }

               if(ASK_Price <= _l && Market_Last_Order != "Buy" && !SL_Buy)
                 {

                  OpenBuy();

                 }

               _Move_TakeProfit_Positions(mag,_h,_l);

              }
            else
              {

               _Move_TakeProfit_Positions(mag,_h,_l);

               Market_Last_Order = "";

               SL_Buy = false;
               SL_Sell = false;

              }

           }
         else
            if(Type_Trade_How == Simple)
              {

               if(BID_Price >= _h)
                 {

                  if(/*!ob &&*/ !os && tt && !SL_Sell)
                    {

                     OpenSell();

                    }

                  if(ob)
                    {

                     if(CloseBuy("Close Buy " + comx))
                       {
                        if(prnlog)
                           Print("<---  _h = ", st5(_h), __LINE__, " CloseBuy  Bid = ", Bid, "   ", DoubleToString((Bid - _h) / point, 0));
                       }
                    }
                 }

               if(ASK_Price <= _l)
                 {


                  if(!ob /*&& !os*/ && tt && !SL_Buy)
                    {

                     OpenBuy();

                    }


                  if(os)
                    {
                     if(CloseSell("Close Sell " + comx))
                       {
                        if(prnlog)
                           Print("<---  _l+sp =  ",  __LINE__, "  ", st5(_l), "  CloseSell by Ask Line  ", Ask, "   ", DoubleToString((_l - Ask) / point, 0));

                       }
                    }

                 }

              }
 

        }

     }

   //*****************************************************************************************
   void              SetNextBallans(double mh, double ml, double &mhBal, double &mlBal)
     {
      double TickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double Setparam = 0.0;
      double balBuyUp = 0, balSellDown = 0, balBuyDown = 0, balSellUp = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(poS.SelectByIndex(i))
           {
            if(CheckPosition())
              {
               if(poS.PositionType() == POSITION_TYPE_BUY)
                 {
                  balBuyUp += poS.Volume() * TickValue * ((mh - poS.PriceOpen()) / point) + poS.Commission() + poS.Swap();
                  balBuyDown += poS.Volume() * TickValue * ((ml - poS.PriceOpen()) / point) + poS.Commission() + poS.Swap();
                 }
               else
                  if(poS.PositionType() == POSITION_TYPE_SELL)
                    {
                     balSellDown +=  poS.Volume() * TickValue * ((poS.PriceOpen() - ml) / point) + poS.Commission() +  poS.Swap();
                     balSellUp +=  poS.Volume() * TickValue * ((poS.PriceOpen() - mh) / point) + poS.Commission() +  poS.Swap();
                    }
              }
           }
        }
      mhBal = acc.Balance() + balSellUp + balBuyUp;
      mlBal = acc.Balance() + balSellDown + balBuyDown;
      // Print ( "balSellUP = ", balSellUp, " balBuyUP = ", balBuyUp,"      ","balSellDown = ", balSellDown, " balBuyDown = ", balBuyDown);
     }


   bool              OpenSellLimit(double lot, double mh, double ml)
     {
      if(acc.Balance() < MinBallance)
        {
         Print("Check MinBallance!");
         return false;
        }

      double _opprice = 0;
      mh = NormalizeDouble(mh, digits);
      ml = NormalizeDouble(ml, digits);
      if(Bid >= mh)
        {
         _opprice = Bid;
         os = true;
        }
      else
        {
         _opprice = mh;
         osl = true;
        }
      CheckHistory();
      if(prnlog)
         Print("<---   ", __LINE__, "  hs = ", hs);
      //Print (st2(lot));

      if(hs)
        {
         while(lot > MAXLOT)
           {
            lot = lot - MAXLOT;
           }
         if(lot < MINLOT)
            return false ;

         if(CheckMargin)
           {

            double need_marg = 0;
            bool o = OrderCalcMargin(ORDER_TYPE_SELL, sym, lot, _opprice, need_marg);
            if(prnlog)
               Print("<---   ", __LINE__, "  need_marg = ", need_marg, "  MAGIC = ", mag);
            if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) - need_marg <= 0)
               return false;
           }
         if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
            return false;

         double tp = 0;
         if(hedge)
            tp = ml;


         //ticket_last_order = trade.SellLimit(lot, _opprice, sym, 0.0, tp, 0, 0, comx);
         if(trade.SellLimit(lot, _opprice, sym, 0.0, tp, 0, 0, comx))
           {



            if(prnlog)
               Print("<---   ", __LINE__, "  ", GetLastError(), "  SellLimit    ", lot);
            return true;
           }
         else
            return false;
        }
      return false;
     }
   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+
   bool              OpenBuyLimit(double lot, double mh, double ml)
     {

      if(acc.Balance() < MinBallance)
        {
         Print("Check MinBallance!");
         return false;
        }

      double _opprice = 0;
      ml = NormalizeDouble(ml, digits);
      mh = NormalizeDouble(mh, digits);
      if(Ask <= ml)
        {

         _opprice = Ask;
         ob = true;
        }
      if(Ask > ml)
        {
         _opprice = ml;
         obl = true;
        }



      CheckHistory();
      if(prnlog)
         Print("<---   ", __LINE__, "  hb = ", hb);

      if(hb)
        {
         while(lot > MAXLOT)
           {
            lot = lot - MAXLOT;
           }
         if(lot < MINLOT)
            return false;

         if(CheckMargin)
           {
            double need_marg = 0;
            bool o = OrderCalcMargin(ORDER_TYPE_BUY, sym, lot, _opprice, need_marg);

            if(prnlog)
               Print("<---   ", __LINE__, "  need_marg = ", need_marg, "  MAGIC = ", mag);

            if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) - need_marg < 0)
               return false;
           }
         if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
            return false;
         double tp = 0;
         if(hedge)
            tp = mh;
         trade.BuyLimit(lot, _opprice, sym, 0.0, tp, 0, 0, comx);
           {
            if(prnlog)
               Print("<---   ", __LINE__, "  ", GetLastError(), "  Buylimit   ", mag);
            return true;
           }
         //else
         //   return false;
        }
      return false;
     }



   //************************************************************
   double            LotsOptimized(double price, ENUM_ORDER_TYPE type, double CouBal)
     {
      double lot;
      if(Lot > 0)
        {
         lot = NormalizeDouble(Lot, MLL);
         if(lot < MINLOT)
            lot = MINLOT;
         return(lot);
        }

      if(Risk <= 0)
         return -100;

      double eq = 1.0;
      double Margalot1 = acc.MarginCheck(sym, type, 1, price);
      if(CouBal <= 0)
         CouBal = acc.Equity();
      CouBal = MathCeil(CouBal);
      if(Margalot1 == 0)
         return - 1;
      lot = CouBal * Risk / Margalot1;
      lot = MathCeil((lot * 100) - 1) / 100;

      // Multiply lot for negative trades



      if(lot > 2.00)
         lot = NormalizeDouble(lot, 1);
      else
         lot = NormalizeDouble(lot, MLL);
      if(lot < MINLOT)
         lot = MINLOT;




      return(lot);
     }

   //+------------------------------------------------------------------+
   //|                                                                  |
   bool              CloseBuy(string _com1)
     {
      ZeroMemory(r);
      ZeroMemory(xr);
      bool o = false;
      double DealProfit = 0.0;
      for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
        {
         if(poS.SelectByIndex(cnt))
           {
            if(CheckPosition())
              {
               if(poS.PositionType() == POSITION_TYPE_BUY)
                 {

                  r.action   = TRADE_ACTION_DEAL;       // тип торговой операции
                  r.position = PositionGetTicket(cnt);         // тикет позиции
                  r.symbol   = sym;         // символ
                  r.volume   = poS.Volume();                  // объем позиции
                  r.magic    = mag;
                  r.type = ORDER_TYPE_SELL;

                  if(Filling_Type == IOC)
                    {
                     r.type_filling = ORDER_FILLING_IOC;
                    }
                  else
                    {
                     r.type_filling = ORDER_FILLING_FOK;
                    }


                  //r.comment = _com1 + "(" + DoubleToString(Ask, digits) + ")";

                  int o1 = OrderSend(r, xr);
                  m_last_trade = TimeCurrent();



                 }
              }
           }
        }
      return o;
     }
   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+
   bool              CloseSell(string _com1)
     {
      ZeroMemory(r);
      ZeroMemory(xr);
      bool o = false;
      double DealProfit = 0.0;
      for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
        {
         if(poS.SelectByIndex(cnt))
           {
            if(CheckPosition())
              {
               if(poS.PositionType() == POSITION_TYPE_SELL)
                 {
                  r.action   = TRADE_ACTION_DEAL;       // тип торговой операции
                  r.position = PositionGetTicket(cnt);         // тикет позиции
                  r.symbol   = sym;         // символ
                  r.volume   = poS.Volume();
                  r.magic    = mag;
                  r.type = ORDER_TYPE_BUY;

                  if(Filling_Type == IOC)
                    {
                     r.type_filling = ORDER_FILLING_IOC;
                    }
                  else
                    {
                     r.type_filling = ORDER_FILLING_FOK;
                    }

                  //r.comment = _com1 + "(" + DoubleToString(Ask, digits) + ")";


                  int o1 = OrderSend(r, xr);
                  m_last_trade = TimeCurrent();



                 }
              }
           }
        }
      return o;
     }

   //*****************************************************************************************
   void              ModifyOrders(double mh, double ml)
     {
      mh = NormalizeDouble(mh, digits);
      ml = NormalizeDouble(ml, digits);
      double SetBalBL = SetNextBallansBuyLimit(ml);
      double SetBalSL = SetNextBallansSellLimit(mh);
      double countlotBL = LotsOptimized(ml, ORDER_TYPE_BUY, SetBalBL);
      double countlotSL = LotsOptimized(mh, ORDER_TYPE_SELL, SetBalSL);
      double lotbuy = LotBuy();
      double lotsell = LotSell();


      if(hedge || !tt)
        {
         for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
           {
            if(poS.SelectByIndex(cnt))
              {

               if(CheckPosition())
                 {
                  // Print (mag,"   ", poS.Magic());
                  if(poS.PositionType() == POSITION_TYPE_BUY)
                    {

                     if(MathAbs(poS.TakeProfit() - mh) > point && mh > 0)
                       {
                        double tp = mh;
                        if(tp > Bid)
                          {
                           if(trade.PositionModify(poS.Ticket(), 0, tp))
                             {
                              // Print("<---   ", __LINE__, "  ", "Mod Buy -> tp = ", tp,"  ",mag,"  ", poS.Magic(),"   ", sym,"   ",poS.Symbol());
                             }
                           else
                              if(prnlog)
                                {
                                 Print("<---   ", __LINE__, "  ", _LastError, " BT  ", MathAbs(poS.TakeProfit() - mh), "   OpenPrice = ", poS.PriceOpen(), "  TP = ", tp, "   Bid = ", Bid);
                                 ResetLastError();
                                }
                          }
                       }
                    }

                  if(poS.PositionType() == POSITION_TYPE_SELL)
                    {
                     if(MathAbs(poS.TakeProfit() - ml) > point && ml > 0)
                       {
                        double tp = ml;
                        if(tp < Ask)
                          {
                           if(trade.PositionModify(poS.Ticket(), 0, tp))
                             {
                              // Print("<---   ", __LINE__, "  ", " Mod Sell -> tp = ", ml,"  ",mag,"  ", poS.Magic(),"   ", sym,"   ",poS.Symbol());
                             }
                           else
                              if(prnlog)
                                {
                                 Print("<---   ", __LINE__, "  ", _LastError, "  ST ", MathAbs(poS.TakeProfit() - ml), "   OpenPrice = ", poS.PriceOpen(), "  TP = ", tp, "   Ask = ", Ask, "  ", poS.Ticket());
                                 ResetLastError();
                                }
                          }
                       }
                    }
                 }
              }
           }
        }



      for(int cnt = OrdersTotal() - 1; cnt >= 0; cnt--)
        {
         if(ord.SelectByIndex(cnt))
            if(!CheckOrder())
               continue;
         if(ord.OrderType() == ORDER_TYPE_SELL_LIMIT)
           {
            if(Bid > mh)
               mh = Bid;

            if(MathAbs(ord.PriceOpen() - mh) > point && mh > 0)
              {
               double tp = 0 ;
               if(hedge)
                  tp = ml;
               if(trade.OrderModify(ord.Ticket(), mh, 0, tp, 0, 0))
                 {
                  if(prnlog)
                     Print("<---   ", __LINE__, "  ", " Mod Sell LImit ", ord.OrderType(), "   ", st5(ord.PriceOpen()));
                 }
               if(GetLastError() > 0 && prnlog)
                 {
                  Print("<---   ", __LINE__, "  ", _LastError, " PRice Sell Limit   ", MathAbs(ord.PriceOpen() - mh), "   ", mh);
                  ResetLastError();
                 }
              }
           }
         if(ord.OrderType() == ORDER_TYPE_BUY_LIMIT)
           {
            if(Ask < ml)
               ml = Ask;
            if(MathAbs(ord.PriceOpen() - ml) > point && ml > 0)
              {
               double tp = 0 ;
               if(hedge)
                  tp = mh;
               if(trade.OrderModify(ord.Ticket(), ml, 0, tp, 0, 0))
                 {
                  if(prnlog)
                     Print("<---   ", __LINE__, "  ", " Mod Buy LImit  ", ord.OrderType(), "   ", st5(ord.PriceOpen()));
                 }
               if(GetLastError() > 0 && prnlog)
                 {
                  if(prnlog)
                     Print("<---   ", __LINE__, "  ", _LastError, "  Price Buy Limit    ", MathAbs(ord.PriceOpen() - ml), "   ", ml);
                  ResetLastError();
                 }
              }
           }
        }
     }



   //**********************************************************************************
   double            SetNextBallansBuyLimit(double ml)
     {
      double TickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double Setparam = -EMPTY_VALUE;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(poS.SelectByIndex(i))
           {
            if(CheckPosition())
              {
               if(ord.OrderType() == ORDER_TYPE_SELL)
                  Setparam = acc.Balance() + poS.Volume() * TickValue * ((poS.PriceOpen() - ml) / point) + poS.Commission() + poS.Swap();
              }
           }
        }
      return Setparam;
     }
   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+
   double            SetNextBallansSellLimit(double mh)
     {
      double TickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double Setparam = -EMPTY_VALUE;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(poS.SelectByIndex(i))
           {
            if(CheckPosition())
              {
               if(ord.OrderType() == ORDER_TYPE_BUY)
                  Setparam = acc.Balance() + poS.Volume() * TickValue * ((poS.PriceOpen() - mh) / point) + poS.Commission() + poS.Swap();
              }
           }
        }
      return            Setparam;
     }

   //****************************************************************************************************
   bool              DeleteLimit(ENUM_ORDER_TYPE type)
     {
      bool o = false;
      for(int cnt = OrdersTotal() - 1; cnt >= 0; cnt--)
        {
         if(ord.SelectByIndex(cnt))
           {
            if(CheckOrder())
              {
               if(ord.OrderType() == type && ord.Ticket() > 0)
                 {
                  o = trade.OrderDelete(ord.Ticket());
                  if(o && prnlog)
                    {
                     Print("<---   ", __LINE__, "  ", o, "   ", _LastError, "  DellLimit   ", type);
                     ResetLastError();
                    }
                  if(o)
                     return o;
                 }
              }
           }
        }
      return o;
     }

   //**********************************************************************************

   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+




   bool              StopLoss(MqlDateTime& t1)
     {



      if(Rollover(t1))
         return false;

      if(sl <= 0)
         return false;

      bool oc = false;
      int _stl = sl;

      for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
        {
         if(poS.SelectByIndex(cnt))
           {
            if(CheckPosition())
              {
               if(poS.PositionType() == POSITION_TYPE_BUY)
                 {
                  if(Ask < poS.PriceOpen() - _stl * point)
                    {
                     CloseBuy("--->! SL " + comx);
                     hb = false;
                     oc = true;
                     SL_Buy = true;
                     if(prnlog)
                        Print("<--- Stoploss for BUY , Price = ", Bid, "  ", __LINE__, "  ", _LastError);
                    }
                 }

               if(poS.PositionType() == POSITION_TYPE_SELL)
                 {
                  if(Bid > poS.PriceOpen() + _stl * point)
                    {
                     CloseSell("--->! SL " + comx);
                     SL_Sell = true;
                     oc = true;
                     hs = false;
                     if(prnlog)
                        Print("<--- Stoploss for SELL , Price = ",  Ask, "  ", __LINE__, "  ", _LastError, " hs = ", hs);
                    }
                 }
              }
           }
        }
      return oc;
     }

   //***************************************************************************************
   void              CheckOpen(bool & _ob, bool & _os, bool & _obl, bool & _osl)
     {
      _ob = false;
      _os = false;
      _obl = false;
      _osl = false;
      int ord_type = -1;
      for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
        {
         if(poS.SelectByIndex(cnt))
           {
            if(CheckPosition())
              {
               ord_type = poS.PositionType();
               if(ord_type == POSITION_TYPE_BUY)
                  _ob = true;
               if(ord_type == POSITION_TYPE_SELL)
                  _os = true;
              }
           }
        }
      for(int cnt = OrdersTotal() - 1; cnt >= 0; cnt--)
        {
         if(ord.SelectByIndex(cnt))
           {
            if(CheckOrder())
               ord_type = ord.OrderType();
            if(ord_type == ORDER_TYPE_BUY_LIMIT)
               _obl = true;
            if(ord_type == ORDER_TYPE_SELL_LIMIT)
               _osl = true;
           }
        }
     }

   //*******************************************************************************
   double            GetOrdLots(ENUM_ORDER_TYPE type)
     {
      double lots = 0;
      for(int cnt = OrdersTotal() - 1; cnt >= 0; cnt--)
        {
         if(ord.SelectByIndex(cnt))
           {
            if(ord.OrderType() == type)
              {
               if(CheckOrder())
                  lots += ord.VolumeInitial();
              }
           }
        }
      return lots;
     }

   double            GetPosLots(ENUM_POSITION_TYPE type)
     {
      double lots = 0;
      for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
        {
         if(poS.SelectByIndex(cnt))
           {
            if(poS.PositionType() == type)
              {
               if(CheckPosition())
                  lots += poS.Volume();
              }
           }
        }
      return lots;
     }



   //**************************************************************************
   bool              CheckOrder()
     {
      if(ord.Symbol() == sym && ord.Magic() == mag)
         return true;
      return false;
     }


   bool              CheckPosition()
     {
      if(poS.Magic() == mag && poS.Symbol() == sym)
         return true;
      return false;
     }

   //***************************************************************************

   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+
   void              CheckHistory()
     {
      hb = true;
      hs = true;
      long posID = -1;
      if(sl == 0)
         return;
      double clprice = -1;
      datetime cltime = 0;
      ENUM_DEAL_TYPE type = -1;
      HistorySelect(TimeCurrent() - 3600 * 6, TimeCurrent());
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         deal.SelectByIndex(i);
         if(deal.Symbol() == sym && deal.Entry() == DEAL_ENTRY_OUT && deal.Magic() == mag)
           {
            clprice = deal.Price();
            cltime = deal.Time();
            posID = HistoryDealGetInteger(deal.Ticket(), DEAL_POSITION_ID);
           }

         if(clprice > 0)
           {
            if(deal.Symbol() == sym && deal.Entry() == DEAL_ENTRY_IN && deal.Magic() == mag)
              {
               if(posID == HistoryDealGetInteger(deal.Ticket(), DEAL_POSITION_ID))
                 {
                  opprice = deal.Price();
                  type = deal.DealType();
                  break;
                 }
              }
           }
        }
      if(TimeCurrent() < cltime + 8 * 60 * 60)
        {
         if(type == DEAL_TYPE_BUY && (opprice - clprice) >= sl * point - 10 * point)
            hb = false;
         if(type == DEAL_TYPE_SELL && (opprice - clprice) <= -sl * point + 10 * point)
            hs = false;
         // if (type>=0)
         //Print(type,"   ",opprice,"   ",clprice);
        }
     }

   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+
   double            LotBuy()
     {
      double lot = 0.0;
      for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
        {
         if(poS.SelectByIndex(cnt))
           {
            if(CheckPosition())
              {
               if(poS.PositionType() == POSITION_TYPE_BUY)
                  lot += ord.VolumeInitial();
              }
           }
        }
      for(int cnt = OrdersTotal() - 1; cnt >= 0; cnt--)
        {
         if(ord.SelectByIndex(cnt))
           {
            if(CheckOrder())
              {
               if(ord.OrderType() == ORDER_TYPE_BUY_LIMIT)
                  lot +=  poS.Volume();
              }
           }
        }
      return lot;
     }


   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+
   double            LotSell()
     {
      double lot = 0.0;
      for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
        {
         if(poS.SelectByIndex(cnt))
           {
            if(CheckPosition())
              {
               if(poS.PositionType() == POSITION_TYPE_SELL)
                  lot += poS.Volume();
              }
           }
        }
      for(int cnt = OrdersTotal() - 1; cnt >= 0; cnt--)
        {
         if(ord.SelectByIndex(cnt))
           {
            if(CheckOrder())
              {
               if(ord.OrderType() == ORDER_TYPE_SELL_LIMIT)
                  lot += ord.VolumeInitial();
              }
           }
        }
      return lot;
     }


   bool              Rollover(MqlDateTime& dt)
     {


      if(dt.hour == 23 && dt.min >= 50)
         return true;

      if(dt.hour == 0)
         return true;

      if(dt.hour == 1 && dt.min <= 30)
         return true;

      return false;
     }

   double            Price_Fill;

   void              CheckOpen(bool & _ob, bool & _os)
     {
      _ob = false;
      _os = false;
      int ord_type = -1;
      for(int cnt = PositionsTotal() - 1; cnt >= 0; cnt--)
        {
         if(poS.SelectByIndex(cnt))
           {
            if(CheckPosition())
              {
               ord_type = poS.PositionType();
               if(ord_type == POSITION_TYPE_BUY)
                 {
                  _ob = true;
                 }
               if(ord_type == POSITION_TYPE_SELL)
                 {
                  _os = true;
                 }
              }
           }
        }

     }

   bool              OpenBuy()
     {

      if(acc.Balance() < MinBallance)
        {
         Print("Check MinBallance!");
         return false;
        }
      bool o = -1;
      CheckHistory();
      //Print ("hb  = ", hb);
      trade.SetExpertMagicNumber(mag);

      double lot = LotsOptimized(Ask, ORDER_TYPE_BUY, acc.Balance());
      lot = Get_DobleLotByMinus(lot,"Market");

      if(lot < 0)
         return false;

      if(lot > MAXLOT)
         lot = MAXLOT;
      opprice = Ask;

      double Slippage;

      SL_Sell = false;

      lot = Get_DobleLotByMinus(lot,"Market");



      if(CheckMargin)
        {
         double need_marg = 0;
         o = OrderCalcMargin(ORDER_TYPE_BUY, sym, lot, opprice, need_marg);
         if(prnlog)
            Print("<---   ", __LINE__, "  need_marg = ", need_marg);
        }
      if(hb)
        {
         if(!CheckMoneyForTrade(sym, lot, ORDER_TYPE_BUY))
            return false;

         m_inicial_trade = TimeCurrent();
         o = trade.Buy(lot, sym, opprice, 0.0, 0.0);

         if(o > 0)
           {

            MqlTradeResult result;
            trade.Result(result);

            Slippage = (opprice - result.price)/Point();


            if(VisualiseOutput)
              {
               TextCreate(DoubleToString(TimeCurrent()),TimeCurrent() - 1000,opprice,"Slippage: "+IntegerToString(int(MathAbs(Slippage))),7,clrWhite,ANCHOR_RIGHT_LOWER);
              }

            Market_Last_Order = "Buy";




           }
        }
      if(o > 0)
        {
         if(prnlog)
            Print("<---  op_BUY   ", __LINE__, "  ", mag);
         return true;
        }
      else
         return false;
     }
   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+
   bool              OpenSell()
     {

      if(acc.Balance() < MinBallance)
        {
         Print("Check MinBallance!");
         return false;
        }
      bool o = 0;
      CheckHistory();

      //com = NULL;
      // if(!IsOptimization() && !IsTesting())
      double lot = LotsOptimized(Ask, ORDER_TYPE_SELL, acc.Balance());

      lot = Get_DobleLotByMinus(lot,"Market");

      if(lot < 0)
         return false;

      if(lot > MAXLOT)
         lot = MAXLOT;
      opprice = Bid;
      double Slippage;
      double need_marg = 0;


      SL_Buy = false;


      o = OrderCalcMargin(ORDER_TYPE_SELL, sym, lot, opprice, need_marg);
      if(prnlog)
         Print("<---   ", __LINE__, "  need_marg = ", need_marg);
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) - need_marg < 0)
         return false;
      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
         return false;

      if(hs)
        {
         if(!CheckMoneyForTrade(sym, lot, ORDER_TYPE_SELL))
            return false;

         m_inicial_trade = TimeCurrent();
         o = trade.Sell(lot, sym, opprice, 0.0, 0.0);
         if(o > 0)
           {

            MqlTradeResult result;
            trade.Result(result);

            Slippage = (opprice - result.price)/Point();


            if(VisualiseOutput)
              {
               TextCreate(DoubleToString(TimeCurrent()),TimeCurrent() - 1000,opprice,"Slippage: "+IntegerToString(int(MathAbs(Slippage))),7,clrWhite,ANCHOR_RIGHT_LOWER);
              }

            Market_Last_Order = "Sell";




           }



        }
      if(o > 0)
        {
         if(prnlog)
            Print("<---  op_SELL   ",  __LINE__, "  ", mag);
         return true;
        }
      else
         return false;
     }

   //****************************************************************
   string            st5(double x)
     {
      return DoubleToString(x, 5);
     }

   string            st2(double x)
     {
      return DoubleToString(x, 2);
     }
  };
//+------------------------------------------------------------------+
sinput int                 inMinTrades = 50;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades =  TesterStatistics(STAT_TRADES);
   if(trades < inMinTrades)
      return 0;
   else
      return TesterStatistics(STAT_PROFIT) / TesterStatistics(STAT_EQUITY_DDREL_PERCENT)  * MathSqrt(trades);
  }

bool              CheckMoneyForTrade(string symb, double lots, ENUM_ORDER_TYPE type)

  {
//--- получим цену открытия
   MqlTick mqltick;
   SymbolInfoTick(symb, mqltick);
   double price = mqltick.ask;
   if(type == ORDER_TYPE_SELL)
      price = mqltick.bid;
//--- значения необходимой и свободной маржи
   if(CheckMargin)
     {
      double margin, free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      //--- вызовем функцию проверки
      if(!OrderCalcMargin(type, symb, lots, price, margin))
        {
         //--- что-то пошло не так, сообщим и вернем false
         //Print("Error in ", __FUNCTION__, " code=", GetLastError());
         return(false);
        }
      //--- если не хватает средств на проведение операции
      if(margin > free_margin)
        {
         //--- сообщим об ошибке и вернем false
         //Print("Not enough money for ", EnumToString(type), " ", lots, " ", symb, " Error code=", GetLastError());
         return(false);
        }
     }
//--- проверка прошла успешно
   return(true);
  }
//+------------------------------------------------------------------+

input double               TotalRisk = 0.05;

input int StartHour = 20;
input int EndHour = 2;
input int Sl = 0 ;



enum enum_multiply
  {
   Dont_Multiply,
   Multiply_By_1_Minus_Trade,
   Multiply_By_Minus_Trade,
   Multiply_By_Plus_Trade,
   Multiply_By_Balance
  };


enum enum_type_Trade
  {
   Simple,
   Trail_TakeProfit,
//Allow_Multiple_Trades
  };



input group "------------New Params UW--------------"
input group "MaxTradeHours"
input int MaxTradeHours = 6;
input bool Active_MaxTradeHours = false;
input group "MaxDailyChange_Percentage"
input double MaxDailyChange_Percentage = 0.2;
input bool Active_MaxDailyChange = false;
bool Check_MaxDailyChange = false;
input group "Lot Multiply By Negative Trade"
input double Lot_Multiply = 1.5;
input double Plus_Balance = 0;
input enum_multiply        Multiply_Type = Dont_Multiply;
input group "Market Hedge"
input enum_type_Trade Type_Trade_How = Simple;
//input double Multiple_Trades_Sensibility_Percent = 0.8;


string Market_Last_Order = "";

bool Allow_Buy = true;
bool Allow_Sell = true;
//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2012, CompanyName |
//|                                  http://www.company"Gr"+name.net |
//+------------------------------------------------------------------+



#include <Canvas\Canvas.mqh>
CCanvas ccanvas;
CCanvas ccanvas1;
class Graf
  {
public:


   bool              fr1;
   bool              show;



                     Graf(void)
     {
      fr1 = true;
      ObjectCreate(0, "XGrafic", OBJ_BUTTON, 0, 0, 0);
      SetButton1("XGrafic", "Show", 20, 65, 40, 15, clrRed, 8, false);
      show = false;

     };
                    ~Graf(void)
     {

      Comment("");
      ObjectDelete(0, "XGrafic");

     };



   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+

   void              GrafA()
     {


      if(ObjectFind(0, "GrBal") < 0)
         ObjectCreate(0, "GrBal", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "GrBal", OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, "GrBal", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "GrBal", OBJPROP_XDISTANCE, 140);
      ObjectSetInteger(0, "GrBal", OBJPROP_YDISTANCE, 10);

      if(ObjectFind(0, "GrDD") < 0)
         ObjectCreate(0, "GrDD", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "GrDD", OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, "GrDD", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "GrDD", OBJPROP_XDISTANCE, 105);
      ObjectSetInteger(0, "GrDD", OBJPROP_YDISTANCE, 60);


      double Ballance = AccountInfoDouble(ACCOUNT_BALANCE);
      double Profit = AccountInfoDouble(ACCOUNT_PROFIT);
      double Percent = Profit / Ballance * 100;
      string Text1 = DoubleToString(Ballance, 2);


      //ObjectSetString(0,"Bal",account,60,"Arial",ColorText);
      ObjectSetInteger(0, "GrBal", OBJPROP_FONTSIZE, 45);
      ObjectSetInteger(0, "GrBal", OBJPROP_COLOR, clrGold);
      ObjectSetString(0, "GrBal", OBJPROP_FONT, "Arial");
      ObjectSetString(0, "GrBal", OBJPROP_TEXT, Text1);

      string Text2 = DoubleToString(Profit, 1) + "  " + DoubleToString(Percent, 1) + "%";
      color clr = clrGold;
      if(Profit > 0)
         clr = clrLawnGreen;
      if(Profit < 0)
         clr = clrLavenderBlush;

      ObjectSetInteger(0, "GrDD", OBJPROP_FONTSIZE, 45);
      ObjectSetInteger(0, "GrDD", OBJPROP_COLOR, clr);
      ObjectSetString(0, "GrDD", OBJPROP_FONT, "Arial");
      ObjectSetString(0, "GrDD", OBJPROP_TEXT, Text2);

     }

   void              GrafB()
     {

      if(ObjectFind(0, "Gr_canvas") < 0)
        {
         ccanvas.CreateBitmapLabel("Gr_canvas", 120, 5, 1400, 65, COLOR_FORMAT_ARGB_NORMALIZE);
         ccanvas.Erase(ColorToARGB(clrBlack, 0));
         ccanvas.FontSet("Arial", -450);
        }

      if(ObjectFind(0, "Gr_canvas1") < 0)
        {
         ccanvas1.CreateBitmapLabel("Gr_canvas1", 90, 65, 1400, 65, COLOR_FORMAT_ARGB_NORMALIZE);
         ccanvas.Erase(ColorToARGB(clrWhite, 0));
         ccanvas1.FontSet("Arial", -450);
        }


      double Ballance = AccountInfoDouble(ACCOUNT_BALANCE);
      double Profit = AccountInfoDouble(ACCOUNT_PROFIT);
      double Percent = Profit / Ballance * 100;
      string Text1 = DoubleToString(Ballance, 2);

      string Text2 = DoubleToString(Profit, 1) + "  " + DoubleToString(Percent, 1) + "%";


      ccanvas.Erase(ColorToARGB(clrBlack, 0));
      ccanvas.TextOut(10, 0, Text1, ColorToARGB(clrGold, 255));
      ccanvas.Update(true);
      color clr = clrGold;
      if(Profit > 0)
         clr = clrLawnGreen;
      if(Profit < 0)
         clr = clrLavenderBlush;

      ccanvas1.Erase(ColorToARGB(clrBlack, 0));
      ccanvas1.TextOut(10, 0, Text2, ColorToARGB(clr, 255));
      ObjectSetInteger(0, "Gr_canvas1", OBJPROP_XDISTANCE, 81);
      ObjectSetInteger(0, "Gr_canvas1", OBJPROP_XDISTANCE, 80);
      ccanvas1.Update(true);
     }


   //+------------------------------------------------------------------+
   //|                                                                  |
   //+------------------------------------------------------------------+
   void              Grafl(double _h, double _l, string _com = "")
     {

      string sh = "GrHigh " + _com;
      string sl = "GrLow " + _com;

      if(ObjectFind(0, sh) < 0 || ObjectFind(0, sl) < 0)
        {
         ObjectCreate(0, sh, OBJ_HLINE, 0, 0, 0);
         ObjectCreate(0, sl, OBJ_HLINE, 0, 0, 0);

         ObjectSetInteger(0, sl, OBJPROP_COLOR, clrRoyalBlue);
         ObjectSetInteger(0, sh, OBJPROP_COLOR, clrCrimson);
        }
      ObjectSetDouble(0, sh, OBJPROP_PRICE, 0.0);
      ObjectSetDouble(0, sl, OBJPROP_PRICE, 0.0);

      ObjectSetInteger(0, sh, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, sl, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, sh, OBJPROP_WIDTH, 0);
      ObjectSetInteger(0, sl, OBJPROP_WIDTH, 0);

      if(!ObjectSetDouble(0, sh, OBJPROP_PRICE, _h))
        {
         Print(_LastError);
         ResetLastError();
        }
      if(!ObjectSetDouble(0, sl, OBJPROP_PRICE, _l))
        {
         Print(_LastError);
         ResetLastError();
        }
     }



   void              SetButton1(string name, string text, int y = 40, int x = 140, int vsize = 150, int hsize = 25, color Color = clrRed, int FontSize = 8, bool state = false)
     {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, vsize);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, hsize);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      if(!state)
         ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrRed); //цвет исходного фона
      if(state)
         ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrGreen); //цвет исходного фона   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrBlack);//рамка
      ObjectSetInteger(0, name, OBJPROP_BACK, false); //фон
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true); //в списке объектов
      ObjectSetInteger(0, name, OBJPROP_STATE, state); // кнопка нажата/отжата
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSize); //размер шрифта
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 9999999999999); // приоритет нажатия
     }

   bool              CreateLabel(const long           chart_ID = 0,             // chart's ID
                                 const string           name = "Bl_100",       // label name
                                 const int              sub_window = 0,           // subwindow index
                                 const int              x = 228,                    // X coordinate
                                 const int              y = 20,                    // Y coordinate
                                 const int              width = 210,               // width
                                 const int              height = 200,              // height
                                 const color            back_clr = clrBlack, // background color
                                 const ENUM_BORDER_TYPE border = BORDER_RAISED,   // border type
                                 const ENUM_BASE_CORNER corner = CORNER_RIGHT_UPPER, // chart corner for anchoring
                                 const color            clr = clrBlack,             // flat border color (Flat)
                                 const ENUM_LINE_STYLE  style = STYLE_SOLID,      // flat border style
                                 const int              line_width = 1,           // flat border width
                                 const bool             back = false,             // in the background
                                 const bool             selection = false,        // highlight to move
                                 const bool             hidden = true,            // hidden in the object list
                                 const long             z_order = 0)              // priority for mouse click
     {
      //--- reset the error value
      ResetLastError();
      //--- create a rectangle label
      if(!ObjectCreate(chart_ID, name, OBJ_RECTANGLE_LABEL, sub_window, 0, 0))
        {
         Print(__FUNCTION__,
               ": failed to create a rectangle label! Error code = ", GetLastError());
         return(false);
        }
      //--- set label coordinates
      ObjectSetInteger(chart_ID, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(chart_ID, name, OBJPROP_YDISTANCE, y);
      //--- set label size
      ObjectSetInteger(chart_ID, name, OBJPROP_XSIZE, width);
      ObjectSetInteger(chart_ID, name, OBJPROP_YSIZE, height);
      //--- set background color
      ObjectSetInteger(chart_ID, name, OBJPROP_BGCOLOR, clrRed);
      //--- set border type
      ObjectSetInteger(chart_ID, name, OBJPROP_BORDER_TYPE, border);
      //--- set the chart's corner, relative to which point coordinates are defined
      ObjectSetInteger(chart_ID, name, OBJPROP_CORNER, corner);
      //--- set flat border color (in Flat mode)
      ObjectSetInteger(chart_ID, name, OBJPROP_COLOR, clrRed);
      //--- set flat border line style
      ObjectSetInteger(chart_ID, name, OBJPROP_STYLE, style);
      //--- set flat border width
      ObjectSetInteger(chart_ID, name, OBJPROP_WIDTH, line_width);
      //--- display in the foreground (false) or background (true)
      ObjectSetInteger(chart_ID, name, OBJPROP_BACK, back);
      //--- enable (true) or disable (false) the mode of moving the label by mouse
      ObjectSetInteger(chart_ID, name, OBJPROP_SELECTABLE, selection);
      ObjectSetInteger(chart_ID, name, OBJPROP_SELECTED, selection);
      //--- hide (true) or display (false) graphical object name in the object list
      ObjectSetInteger(chart_ID, name, OBJPROP_HIDDEN, hidden);
      //--- set the priority for receiving the event of a mouse click in the chart
      ObjectSetInteger(chart_ID, name, OBJPROP_ZORDER, z_order);
      //--- successful execution

      return(true);
     }

  };

Graf graf;






//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Visual_Output()
  {
// Print (ObjectGetInteger(0, "XGrafic", OBJPROP_STATE));
   if(ObjectGetInteger(0, "XGrafic", OBJPROP_STATE) == false)
     {
      graf.show = false;
      ObjectsDeleteAll(0, "Gr");
      graf.show = false;
      graf.SetButton1("XGrafic", "Show", 20, 65, 40, 15, clrRed, 8, false);
      Comment("");
     }

   if(ObjectGetInteger(0, "XGrafic", OBJPROP_STATE) == true)
     {
      graf.show = true;
      graf.SetButton1("XGrafic", "Hide", 20, 65, 40, 15, clrGreen, 8, true);
      graf.fr1 = true;
     }


   ChartRedraw();
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
  {
   if(VisualiseOutput)
     {

      if(sparam == "XGrafic")
        {
         Visual_Output();
        }


     }

  }

//+------------------------------------------------------------------+


Fletcher *S1;
MyTrade T;


bool Real = true;



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

int Order_Filling_Mode;
int OnInit()
  {


//--- create timer
   /* EventSetTimer(60);
    if(DFSymbol=="")
      {
       _DFSymbol=Symbol();
      }
    else
      {
       _DFSymbol=DFSymbol;
      }
   //---

    DFC::Start(_DFSymbol,DFPORT,DFIP,DFLogin,DFPassword,AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_NAME),AccountInfoString(ACCOUNT_SERVER));*/


   S1 = new Fletcher(_Symbol, MinPips, PeriodAvg,  PeriodSize_x, MultSize_x, MinWidth, Delta_H, Delta_L);
   T.SetTrade(_Symbol,  StartHour, EndHour, Sl, Mag);

   Risk = TotalRisk;


   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHIFT, true);
   ChartSetInteger(0, CHART_AUTOSCROLL, true);
   ChartSetInteger(0, CHART_SCALE, 1);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, true);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, true);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_VISIBLE_BARS, 2000);
   ChartSetInteger(0, CHART_COLOR_ASK, clrGold);
   return(INIT_SUCCEEDED);
  }



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade()
  {
//m_last_trade = TimeCurrent();
  }

double dealPrice;
double orderPrice;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
  {



   if(Trade_type == LIMIT)
     {


      double slippage;


      // Result of trade request execution
      ulong lastOrderID = trans.order;
      ENUM_ORDER_TYPE lastOrderType = trans.order_type;
      ENUM_ORDER_STATE lastOrderState = trans.order_state;

      // The name of the symbol for which a transaction was performed
      string trans_symbol = trans.symbol;

      // Type of transaction
      ENUM_TRADE_TRANSACTION_TYPE trans_type = trans.type;

      switch(trans.type)
        {
         /* case TRADE_TRANSACTION_POSITION:   // Position modification
          {
             ulong pos_ID = trans.position;
             PrintFormat("MqlTradeTransaction: Position #%d %s modified: SL=%.5f TP=%.5f",
                         pos_ID, trans_symbol, trans.price_sl, trans.price_tp);


             dealPrice = trans.price_trigger;

             Print("Price Trigger ", dealPrice);

             break;
          }*/

         case TRADE_TRANSACTION_DEAL_ADD:    // Adding a trade
           {
            ulong lastDealID = trans.deal;
            ENUM_DEAL_TYPE lastDealType = trans.deal_type;

            double lastDealVolume = trans.volume;





            dealPrice = trans.price;

            break;
           }

         case TRADE_TRANSACTION_HISTORY_ADD: // Adding an order to the history
           {
            // Order ID in an external system - a ticket assigned by an Exchange
            string Exchange_ticket = "";
            if(lastOrderState == ORDER_STATE_FILLED)
              {


               if(HistoryOrderSelect(lastOrderID))
                 {

                  Exchange_ticket = HistoryOrderGetString(lastOrderID, ORDER_EXTERNAL_ID);
                  orderPrice = HistoryOrderGetDouble(lastOrderID,ORDER_PRICE_OPEN);


                  if(dealPrice != 0 && orderPrice != 0)
                    {

                     slippage = NormalizeDouble(dealPrice - orderPrice, _Digits) / _Point;



                     if(VisualiseOutput)
                       {
                        TextCreate(DoubleToString(lastOrderID),TimeCurrent() - 300,dealPrice,"Slippage: "+IntegerToString(int(MathAbs(slippage))),7,clrWhite,ANCHOR_RIGHT_LOWER);
                       }

                     dealPrice = 0;
                     orderPrice = 0;
                     //m_last_trade = TimeCurrent();
                     /*Print("dealPrice --------------------------------------", dealPrice);
                     Print("orderPrice --------------------------------------", orderPrice);
                     Print("slippage --------------------------------------", MathAbs(slippage));*/


                    }





                 }

              }

            break;
           }



            /*case TRADE_TRANSACTION_ORDER_UPDATE:
            {

            dealPrice = trans.price;

               Print("----------Price Trigger ", dealPrice);

               break;

            }*/

        }


      ulong orderID_result = result.order;
     }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int z = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {


   /* if(Type_DF == DF)
      {

       while(IsStopped()==false && (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
         {
          if(DFC::GetDFPrice(_DFSymbol,DF_BID,DF_ASK))
            {

             //Print("DFASK : ", DF_ASK,"   DF_BID :",DF_BID);
             ReduceDFSpread(DF_SPREAD_REDUCE_PRC);
             //Print("Spread Mod DFASK : ", DF_ASK,"   DF_BID :",DF_BID);





             if(VisualiseOutput)
               {
                DrawLine("_BID_DF",DF_BID,clrAqua);
                DrawLine("_ASK_DF",DF_ASK,clrFuchsia);

               }


             S1.Run();


             T.Trade(S1.h, S1.l);


             if(Active_MaxTradeHours)
                _CloseAtTimeMinutes(Mag,60 * MaxTradeHours);

             if(VisualiseOutput && MQLInfoInteger(MQL_TESTER) == true)
               {
                Visual_Output();
               }



             if(graf.show && VisualiseOutput)
               {
                string com = "\n" + AccountInfoString(ACCOUNT_NAME) + "\n" + "\n";
                com += "Version - " + (string) __DATETIME__ + "\n" + "Account LEVERAGE - " + DoubleToString(AccountInfoInteger(ACCOUNT_LEVERAGE), 0) + "\n" + "\n";
                com += "MarginCall = " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL), 0) + "%  \nStopOut = " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_SO), 0) + "%\n\n";
                com +=  S1.h - S1.l > 0 ? DoubleToString((S1.h - S1.l) / _Point, 0) : "*"+ "\n";

                Comment(com);

                graf.GrafB();
                graf.Grafl(S1.h, S1.l, "");
               }



            }
          Sleep(1);
         }

      }
    else
       if(Type_DF == MT)
         {*/
   S1.Run();


   T.Trade(S1.h, S1.l);


   if(Active_MaxTradeHours)
      _CloseAtTimeMinutes(Mag,60 * MaxTradeHours);

   if(VisualiseOutput && MQLInfoInteger(MQL_TESTER) == true)
     {
      Visual_Output();
     }



   if(graf.show && VisualiseOutput)
     {
      string com = "\n" + AccountInfoString(ACCOUNT_NAME) + "\n" + "\n";
      com += "Version - " + (string) __DATETIME__ + "\n" + "Account LEVERAGE - " + DoubleToString(AccountInfoInteger(ACCOUNT_LEVERAGE), 0) + "\n" + "\n";
      com += "MarginCall = " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL), 0) + "%  \nStopOut = " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_SO), 0) + "%\n\n";
      com +=  S1.h - S1.l > 0 ? DoubleToString((S1.h - S1.l) / _Point, 0) : "*"+ "\n";

      Comment(com);

      graf.GrafB();
      graf.Grafl(S1.h, S1.l, "");
     }


//}




  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteAllObjects()
  {
   int totalObjects = ObjectsTotal(0);
   for(int i = totalObjects - 1; i >= 0; i--)
     {
      string objectName = ObjectName(0, i);
      ObjectDelete(0, objectName);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

//--- destroy timer
//DFC::Stop();
//ObjectsDeleteAll(0, "Gr");
//DeleteAllObjects();
   ObjectsDeleteAll(0, "_");
   Comment("");
   EventKillTimer();
   delete S1;

  }

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void _CloseAtTimeMinutes(uint _Magic, int _Minutes)
  {
   uint total=PositionsTotal();


   MqlTick _LAST_TICK;
   SymbolInfoTick(Symbol(),_LAST_TICK);

   if(total > 0)
     {

      for(uint i=0; i<total; i++)
        {
         ulong ticket = PositionGetTicket(i);

         //Print(ticket);

         if(poS.Magic() == _Magic)
           {


            ulong Open_Time =  poS.TimeMsc();

            ulong Minutes_To_Milliseconds = _Minutes * 60 * 1000;

            ulong _Close_Position_Time = Open_Time + Minutes_To_Milliseconds;


            ulong Current_Time_Msc = _LAST_TICK.time_msc;


            if(Current_Time_Msc >= _Close_Position_Time)
              {
               trade.PositionClose(ticket);
              }



           }

        }
     }

  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime m_inicial_trade = TimeCurrent();
datetime m_last_trade = TimeCurrent();

double Balance_Minus = 0;

double Last_Doble_Lot = 0.01;
double Last_Doble_Sell = 0.01;
double Last_Doble_Buy = 0.01;

int Initialize_Last_Double_Lot = 0;


double LastRecentTrades = 0;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Get_DobleLotByMinus(double _lot,string Type_Side)
  {




   double Value_Recent_Trades = GetRecentTrades();



   if(LastRecentTrades != Value_Recent_Trades)
     {

      LastRecentTrades = Value_Recent_Trades;


      //Print("Recent Trades ---------------------------------- ", Value_Recent_Trades);
      //Print("Balance_Minus ---------------------------------- ", Balance_Minus);

     }
   else
     {

      Last_Doble_Lot = _lot;
      Last_Doble_Buy = _lot;
      Last_Doble_Sell = _lot;
      return Last_Doble_Lot;
     }



   if(Multiply_Type == Dont_Multiply)
     {

      return _lot;
     }
   else
      if(Multiply_Type == Multiply_By_1_Minus_Trade)
        {

         if(Value_Recent_Trades < 0.0)
           {

            Last_Doble_Lot =  _lot * Lot_Multiply; // Modify the factor as needed
            Last_Doble_Lot = NormalizeDouble(Last_Doble_Lot,2);

           }
         else
           {
            Last_Doble_Lot = _lot;

           }

        }
      else
         if(Multiply_Type == Multiply_By_Minus_Trade)
           {

            if(Value_Recent_Trades < 0.0)
              {


               Last_Doble_Lot =  Last_Doble_Lot * Lot_Multiply; // Modify the factor as needed
               Last_Doble_Lot = NormalizeDouble(Last_Doble_Lot,2);

              }
            else
              {
               Last_Doble_Lot = _lot;

              }

           }
         else
            if(Multiply_Type == Multiply_By_Plus_Trade)
              {

               //Print(Value_Recent_Trades);
               if(Value_Recent_Trades < 0.0)
                 {

                  Last_Doble_Lot = _lot;
                  return Last_Doble_Lot;

                 }
               else
                 {


                  Last_Doble_Lot =  Last_Doble_Lot * Lot_Multiply; // Modify the factor as needed
                  Last_Doble_Lot = NormalizeDouble(Last_Doble_Lot,2);

                 }

              }
            else
               if(Multiply_Type == Multiply_By_Balance)
                 {


                  Balance_Minus += Value_Recent_Trades;



                  if(Initialize_Last_Double_Lot == 0)
                    {
                     Last_Doble_Lot = _lot;
                     Last_Doble_Buy = _lot;
                     Last_Doble_Sell = _lot;
                     Initialize_Last_Double_Lot = 1;
                    }

                  if(Balance_Minus < Plus_Balance)
                    {



                     if(Type_Side == "Sell_Limit")
                       {
                        Last_Doble_Sell *= Lot_Multiply;

                        Last_Doble_Lot = NormalizeDouble(Last_Doble_Sell,2);

                       }
                     else
                        if(Type_Side == "Buy_Limit")
                          {
                           Last_Doble_Buy *= Lot_Multiply;
                           Last_Doble_Lot = NormalizeDouble(Last_Doble_Buy,2);


                          }
                        else
                          {
                           Last_Doble_Lot *= Lot_Multiply;
                           Last_Doble_Lot = NormalizeDouble(Last_Doble_Lot,2);


                          }

                    }
                  else
                    {

                     Balance_Minus = 0;
                     Last_Doble_Lot = _lot;
                     Last_Doble_Sell = _lot;
                     Last_Doble_Buy = _lot;

                     Last_Doble_Lot = NormalizeDouble(Last_Doble_Lot,2);



                    }


                 }


   if(Trade_type == LIMIT)
     {
      m_last_trade = TimeCurrent();
     }





   return Last_Doble_Lot;
  }





//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetRecentTrades()
  {

   if(Trade_type == MARKET)
     {

      if(Multiply_Type == Multiply_By_Balance)
         HistorySelect(m_inicial_trade - 1000,TimeCurrent());
      else
         HistorySelect(m_inicial_trade - 1000,m_last_trade + 1000);
     }
   else
     {
      HistorySelect(m_inicial_trade - 1000,TimeCurrent());
     }


   double total_profit=0;
   uint   total=HistoryDealsTotal();
   ulong  ticket=0;

   if(total > 0)
     {
      for(uint i=0; i<total; i++)
        {
         //--- Get deals ticket
         ticket=HistoryDealGetTicket(i);
         //LogAnyError("HistoryDealGetTicket");

         if(ticket > 0)
           {
            //Skip Withdrawals, Deposits, Transfers
            long historyInteger = HistoryDealGetInteger(ticket,DEAL_ORDER);
            LogAnyError("HistoryDealGetInteger");


            //Try to Skip Balance
            if(historyInteger == 0)
              {
               continue;
              }


            double deal_commission=HistoryDealGetDouble(ticket,DEAL_COMMISSION);
            double deal_swap=HistoryDealGetDouble(ticket,DEAL_SWAP);
            double deal_profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
            double profit=deal_commission+deal_swap+deal_profit;

            total_profit+=profit;



           }


        }
     }


   return(total_profit);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void LogAnyError(string place)
  {
   int err = GetLastError();

   if(err == 0)
     {
      return ;
     }
   Print("Got an error ", err, " on ", place);
   ResetLastError();

  }



//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool TextCreate(
   const string            name="Text",              // nome do objeto
   datetime                time=0,                   // ponto de ancoragem do tempo
   double                  price=0,                  // ponto de ancoragem do preço
   const string            text="Text",              // o próprio texto
   const int               font_size=10,             // tamanho da fonte
   const color             clr=clrRed,               // cor
   const ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT_UPPER // tipo de ancoragem

)
  {
//--- definir as coordenadas de pontos de ancoragem, se eles não estão definidos

   const long              chart_ID=0;// ID do gráfico
   const int               sub_window=0; // índice da sub-janela
   const string            font="Arial";             // fonte
   const double            angle=0.0; // inclinação do texto
   const bool              selection=false;          // destaque para mover
   const long              z_order=0;  // prioridade para clicar no mouse
   const bool              back=false;               // no fundo
   const bool              hidden=true;              // ocultar na lista de objetos

   ChangeTextEmptyPoint(time,price);
//--- redefine o valor de erro
   ResetLastError();
//--- criar objeto Texto
   if(!ObjectCreate(chart_ID,name,OBJ_TEXT,sub_window,time,price))
     {
      Print(__FUNCTION__,
            ": falha ao criar objeto \"Texto\"! Código de erro = ",GetLastError());
      return(false);
     }
//--- definir o texto
   ObjectSetString(chart_ID,name,OBJPROP_TEXT,text);
//--- definir o texto fonte
   ObjectSetString(chart_ID,name,OBJPROP_FONT,font);
//--- definir tamanho da fonte
   ObjectSetInteger(chart_ID,name,OBJPROP_FONTSIZE,font_size);
//--- definir o ângulo de inclinação do texto
   ObjectSetDouble(chart_ID,name,OBJPROP_ANGLE,angle);
//--- tipo de definição de ancoragem
   ObjectSetInteger(chart_ID,name,OBJPROP_ANCHOR,anchor);
//--- definir cor
   ObjectSetInteger(chart_ID,name,OBJPROP_COLOR,clr);
//--- exibir em primeiro plano (false) ou fundo (true)
   ObjectSetInteger(chart_ID,name,OBJPROP_BACK,back);
//--- habilitar (true) ou desabilitar (false) o modo de mover o objeto com o mouse
   ObjectSetInteger(chart_ID,name,OBJPROP_SELECTABLE,selection);
   ObjectSetInteger(chart_ID,name,OBJPROP_SELECTED,selection);
//--- ocultar (true) ou exibir (false) o nome do objeto gráfico na lista de objeto
   ObjectSetInteger(chart_ID,name,OBJPROP_HIDDEN,hidden);
//--- definir a prioridade para receber o evento com um clique do mouse no gráfico
   ObjectSetInteger(chart_ID,name,OBJPROP_ZORDER,z_order);
//--- sucesso na execução
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ChangeTextEmptyPoint(datetime &time,double &price)
  {
//--- se o tempo do ponto não está definido, será na barra atual
   if(!time)
      time=TimeCurrent();
//--- se o preço do ponto não está definido, ele terá valor Bid
   if(!price)
      price=SymbolInfoDouble(Symbol(),SYMBOL_BID);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool HasSufficientMargin(double lotSize,ENUM_ORDER_TYPE orderType)
  {
   double MaintencanceMargin = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_MAINTENANCE);  // Retrieve the required initial margin for the symbol
   double InitialMargin = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);  // Retrieve the required initial margin for the symbol
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);  // Retrieve the free margin of the account


   if(freeMargin < 0)
     {
      return false;

     }
   else
     {
      return true;
     }

//bool a = SymbolInfoMarginRate(_Symbol,orderType,InitialMargin,MaintencanceMargin);

//return a;


  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckSufficientFunds(double lotSize)
  {
   double requiredMargin = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL) * lotSize;  // Calculate the required margin for the lot size

// Retrieve the account balance
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
//double accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);

// Calculate the free margin available in the account
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double accountMargin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = accountEquity - accountMargin;

// Check if there is enough free margin to cover the required margin
   if(freeMargin >= requiredMargin)
     {
      // Sufficient funds available to open the position
      return true;
     }
   else
     {
      // Insufficient funds to open the position
      return false;
     }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawLine(string LineName,double Position,color LineColor=clrYellow,int Style=STYLE_DOT)
  {
   if(ObjectFind(0,LineName)==-1)
     {
      // ObjectCreate(LineName,OBJ_HLINE,0,TimeCurrent(),Position);

      if(!ObjectCreate(0,LineName,OBJ_HLINE,0,0,Position))
        {
         Print(__FUNCTION__,
               ": не удалось создать горизонтальную линию! Код ошибки = ",GetLastError());
         // return(false);
        }

      //--- установим цвет линии
      ObjectSetInteger(0,LineName,OBJPROP_COLOR,LineColor);
      //--- установим стиль отображения линии
      ObjectSetInteger(0,LineName,OBJPROP_STYLE,Style);

      // ObjectSet(LineName,OBJPROP_COLOR,LineColor);
      //    ObjectSet(LineName,OBJPROP_STYLE,Style);
     }
   else
     {
      ObjectSetInteger(0,LineName,OBJPROP_COLOR,LineColor);
      ObjectMove(0,LineName,0,TimeCurrent(),Position);
     }

  }
//+------------------------------------------------------------------+

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CPositionInfo PositionInfo;
CTrade Trade;
void _CloseAllPositions_Buys(uint _magic)
  {
   uint total=PositionsTotal();


   if(total > 0)
     {

      for(uint i=0; i<total; i++)
        {
         ulong ticket = PositionGetTicket(i);

         //Print(ticket);

         if(PositionInfo.Magic() == _magic && PositionInfo.PositionType() == POSITION_TYPE_BUY)
           {

            Trade.PositionClose(ticket);

           }

        }
     }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void _CloseAllPositions_Sells(uint _magic)
  {
   uint total=PositionsTotal();


   if(total > 0)
     {

      for(uint i=0; i<total; i++)
        {
         ulong ticket = PositionGetTicket(i);

         //Print(ticket);

         if(PositionInfo.Magic() == _magic && PositionInfo.PositionType() == POSITION_TYPE_SELL)
           {

            Trade.PositionClose(ticket);

           }

        }
     }

  }



double last_high = 0;
double last_low = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void _Move_TakeProfit_Positions(uint _magic,double high,double low)
  {
   uint total=PositionsTotal();



   if(total > 0)
     {

      for(uint i=0; i<total; i++)
        {
         ulong ticket = PositionGetTicket(i);

         //Print(ticket);

         if(PositionInfo.Magic() == _magic && PositionInfo.PositionType() == POSITION_TYPE_SELL)
           {

            if(low != last_low)
              {
               Trade.PositionModify(ticket,0,low);
               last_low = low;
              }


           }


         if(PositionInfo.Magic() == _magic && PositionInfo.PositionType() == POSITION_TYPE_BUY)
           {

            if(high != last_high)
              {
               Trade.PositionModify(ticket,0,high);
               last_high = high;

              }

           }

        }
     }

  }


//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DestroyLine(string LineName)
  {
   if(ObjectFind(0,LineName)>=0)
      ObjectDelete(0,LineName);
  }
//+------------------------------------------------------------------+