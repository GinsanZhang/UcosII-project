

/*------------------------------------------------------------------------------------------*/
/*                                     include files	                                    */
/*------------------------------------------------------------------------------------------*/
#include "2440lib.h"  
#include "2440addr.h" 
#include "def.h"

#define LED1_ON   ~(1<<5)
#define LED2_ON   ~(1<<6)
#define LED3_ON   ~(1<<7)
#define LED4_ON   ~(1<<8)

#define LED1_OFF   (1<<5)
#define LED2_OFF   (1<<6)
#define LED3_OFF   (1<<7)
#define LED4_OFF   (1<<8)

/*********************************************************************************************
* name:		led_test
* func:		i/o control test(led)
* para:		none
* ret:		none
* modify:
* comment:		
*********************************************************************************************/
void dely(U32 tt)
{
   U32 i;
   for(;tt>0;tt--)
   {
     for(i=0;i<10000;i++){}
   }
}

void led_test1(void)			//指示任务切换	   void OSTaskSwHook (void)
{
	  
		rGPBDAT = rGPBDAT^(LED1_OFF);	
	  
	 
}
 void led_test2(void){						  //指示	
   
	 	    rGPBDAT = rGPBDAT&(LED2_ON);
			dely(30);
			rGPBDAT = rGPBDAT|(LED2_OFF);
			dely(30);
	
 }
 void led_test3(void){
       
			rGPBDAT = rGPBDAT&(LED3_ON);
			dely(30);
			rGPBDAT = rGPBDAT|(LED3_OFF);
			dely(30);
 }
 void led_test4(void){
       
		 	rGPBDAT = rGPBDAT&(LED4_ON);
			dely(30);
			rGPBDAT = rGPBDAT|(LED4_OFF);
			dely(30);
 }
