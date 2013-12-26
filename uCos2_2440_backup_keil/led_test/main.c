
#include "def.h"
#include "option.h"
#include "2440addr.h"     
#include "2440lib.h"
#include "2440slib.h"   
#include "ucos_ii.h" 
#include "app_cfg.h"
#include "led_test.h"   
//================================
#define LED1_OFF   (1<<5)
#define LED2_OFF   (1<<6)
#define LED3_OFF   (1<<7)
#define LED4_OFF   (1<<8)

void	Isr_Init(void);
void target_init(void);
void Timer0Init(void);
   
U8 err; 
OS_STK  MainTaskStk[MainTaskStkLengh];
OS_STK	Task0Stk [Task0StkLengh];       // Define the Task0 stack 
OS_STK	Task1Stk [Task1StkLengh];       // Define the Task1 stack 
OS_STK	Task2Stk [Task2StkLengh];       // Define the Task1 stack 
int main(int argc, char **argv)
{
    target_init();

  	//初始化uC/OS   
   	OSInit ();	 
   	
   	//初始化系统时基
   	OSTimeSet(0);
   	
   	//创建系统初始任务
   	OSTaskCreate(MainTask,(void *)0, &MainTaskStk[MainTaskStkLengh - 1], MainTaskPrio);																										
	
	OSStart ();
	
	return 0;				
  		     
}	 
/******************************************************/
//              多任务
/******************************************************/
 void MainTask(void *pdata){
  #if OS_CRITICAL_METHOD == 3                                /* Allocate storage for CPU status register */
   OS_CPU_SR  cpu_sr;
   #endif
   OS_ENTER_CRITICAL();
  	
	 Timer0Init();//initial timer0 for ucos time tick
	 Isr_Init();   //initial interrupt prio or enable or disable

	OS_EXIT_CRITICAL();
	  OSStatInit();

 	OSTaskCreate (Task0,(void *)0, &Task0Stk[Task0StkLengh - 1], Task0Prio);	
	OSTaskCreate (Task1,(void *)0, &Task1Stk[Task1StkLengh - 1], Task1Prio);		 
    OSTaskCreate (Task2,(void *)0, &Task2Stk[Task2StkLengh - 1], Task2Prio);
 	err=OSTaskSuspend(Task1Prio);
	err=OSTaskSuspend(Task2Prio);
	 while(1){
	     OSTimeDly(1);
	 }
 }

void 	Task0(void *pdata){
    for(;;){
           OSTimeDly(100);		 
		   led_test2();
		   err=OSTaskResume(Task1Prio);
		   err=OSTaskSuspend(Task0Prio);
		 }
}

 void 	Task1(void *pdata){
 for(;;){
		  OSTimeDly(100);
 		  led_test3();
		  err=OSTaskResume(Task2Prio);
		  err=OSTaskSuspend(Task1Prio);
 		 }  
 }

  void 	Task2(void *pdata){
  for(;;){
          OSTimeDly(100);
 		  led_test4();
		  err=OSTaskResume(Task0Prio);
		  err=OSTaskSuspend(Task2Prio);
		  }
 }


/*************************目标板初始化******************************************/
void target_init(){

	   	int i;
	U8 key;
	U32 mpll_val=0;
	 rGPBDAT = rGPBDAT|(LED1_OFF)|(LED2_OFF)|(LED3_OFF)|(LED4_OFF);
     rINTMSK = 0xffffffff;//disable interrupt

	i = 2 ;	//hzh, don't use 100M!
		//boot_params.cpu_clk.val = 3;
	switch ( i ) {
	case 0:	//200
		key = 12;
		mpll_val = (92<<12)|(4<<4)|(1);
		break;
	case 1:	//300
		key = 13;
		mpll_val = (67<<12)|(1<<4)|(1);
		break;
	case 2:	//400
		key = 14;
		mpll_val = (92<<12)|(1<<4)|(1);
		break;
	case 3:	//440!!!
		key = 14;
		mpll_val = (102<<12)|(1<<4)|(1);
		break;
	default:
		key = 14;
		mpll_val = (92<<12)|(1<<4)|(1);
		break;
	}
	
	//init FCLK=400M, so change MPLL first
	ChangeMPllValue((mpll_val>>12)&0xff, (mpll_val>>4)&0x3f, mpll_val&3);	 //400M
	ChangeClockDivider(key, 12);  //1：4：8    					   fclk:400 hclk:100 pclk:50
    
	
	// Port Init
	Port_Init();

	
}

 void Timer0Init(void)
{
	// 定时器设置

	
	rTCON = rTCON & (~0xf) ;			// clear manual update bit, stop Timer0
	
	
	rTCFG0 	&= 0xffffff00;					// set Timer 0&1 prescaler 0
	rTCFG0 |= 15;							//prescaler = 15+1

	rTCFG1 	&= 0xfffffff0;					// set Timer 0 MUX 1/4
	rTCFG1  |= 0x00000001;					// set Timer 0 MUX 1/4
    rTCNTB0 = (PCLK / (4 *15* OS_TICKS_PER_SEC)) - 1;
 
    
    rTCON = rTCON & (~0xf) |0x02;              // updata 		
	rTCON = rTCON & (~0xf) |0x09; 	// start
 }

extern void OSTickISR(void);
void	Isr_Init(){
	// 设置中断控制器
	rPRIORITY = 0x00000000;		// 使用默认的固定的优先级
	rINTMOD = 0x00000000;		// 所有中断均为IRQ中断
	pISR_TIMER0= (UINT32T) OSTickISR;
	rINTMSK &= ~(1<<10);			// 打开TIMER0中断允许
}