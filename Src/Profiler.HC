#help_index "Debugging/Profiler;Profiler;Cmd Line (Typically)/Profiler"
#help_file "::/Doc/Profiler"

#define PF_ARRAY_CNT 0x100000
I64 pf_jiffy_start,pf_jiffy_end;
I64 *pf_array=NULL;
I64 pf_cpu=0;
I64 pf_buf_in_ptr=0,pf_depth;
I64 pf_prof_active=0;

U0 ProfTimerInt(U8 *cur_rip)
{//See $LK,"profiler_timer_irq",A="FF:::/Kernel/KInts.HC,profiler_timer_irq"$.
  I64 i,k;
#ifdef TARGET_RISCV
  I64 *bp=GetRBP;
  if (Bt(&pf_prof_active,0))
    for (k=0;k<=pf_depth;k++) {
      if (k) {
	if(!ChkOnStk(bp,Fs))
	  break;
	i=bp[-1];
	bp=bp[-2];
      } else
        i=cur_rip;
      if (pf_buf_in_ptr<PF_ARRAY_CNT) {
	pf_array[pf_buf_in_ptr++]=i;
	pf_jiffy_end=__GetTicks;
      }
    }
#else
  CTask *task=Fs;
  if (Bt(&pf_prof_active,0))
    for (k=0;k<=pf_depth;k++) {
      if (k)
	i=Caller(k+1);
      else
        i=cur_rip;
      if (pf_buf_in_ptr<PF_ARRAY_CNT) {
	pf_array[pf_buf_in_ptr++]=i;
	pf_jiffy_end=__GetTicks;
      }
    }
#endif
}

public U0 Prof(I64 depth=10,I64 cpu_num=0)
{/*Start collecting profiler statistics.
Profilers report where time is spent
by sampling RIP during the $TX,"",D="DD_JIFFY_HZ"$
timer interrupt.

Do a $LK,"ProfRep",A="MN:ProfRep"$(), (profiler report)
after you have collected data.
*/
  if (!(0<=cpu_num<mp_cnt))
    ST_ERR_ST "Invalid CPU\n";
  else {
    MPSetProfilerInt(NULL,cpu_num,0);

    pf_cpu=cpu_num;

    pf_depth=depth;
    pf_buf_in_ptr=0;
    if (!pf_array)
      pf_array=AMAlloc(sizeof(I64)*PF_ARRAY_CNT);
    pf_jiffy_end=pf_jiffy_start=__GetTicks;
    LBts(&pf_prof_active,0);
    MPSetProfilerInt(&ProfTimerInt,pf_cpu,10000);
  }
}

I64 ProfCompare(U8 *i1,U8 *i2)
{
  return i1-i2;
}

public U0 ProfRep(I64 filter_cnt=1,Bool leave_it=OFF)
{//Profiler report. Call $LK,"Prof",A="MN:Prof"$() first and collect data.
  I64 i,hits,rip,last_rip=0,routine_total=0;
  F64 total_time;
  U8 buf[256],buf2[256],last_buf[256];
  if (!LBtr(&pf_prof_active,0))
    "Profiler Not Active\n";
  if (!pf_buf_in_ptr)
    "No Profiler Statistic\n";
  else {
    if (!(total_time=pf_jiffy_end-pf_jiffy_start))
      total_time=1;
    QSortI64(pf_array,pf_buf_in_ptr,&ProfCompare);
    last_buf[0]=0;
    for (i=0;i<pf_buf_in_ptr;i+=hits) {
      rip=pf_array[i];
      hits=0;
      do hits++;
      while (i+hits<pf_buf_in_ptr && pf_array[i+hits]==rip);

      StrPrint(buf,"%p",rip);
      StrFirstRem(buf,"+",buf2);
      if (StrCmp(buf2,last_buf)) {
	if (last_buf[0] && routine_total>=filter_cnt)
	  "$$GREEN$$%6.2f%08X:%s\n$$FG$$",100*routine_total/total_time,
		routine_total,last_buf;
	StrCpy(last_buf,buf2);
	routine_total=0;
      }
      routine_total+=hits;
      if (hits>=filter_cnt) {
	"%6.2f%08X:%P\n",100*hits/total_time,hits,rip;
	last_rip=rip;
      }
    }
    if (last_buf[0] && routine_total>=filter_cnt)
      "$$GREEN$$%6.2f%08X:%s\n$$FG$$",100*routine_total/total_time,
	    routine_total,last_buf;
    "Total Time:%0.6fs\n",total_time/JIFFY_FREQ;
    if (leave_it) {
      //MPSetProfilerInt(&ProfTimerInt,pf_cpu,10000);
      LBts(&pf_prof_active,0);
    } else
      MPSetProfilerInt(NULL,pf_cpu,0);
  }
}
