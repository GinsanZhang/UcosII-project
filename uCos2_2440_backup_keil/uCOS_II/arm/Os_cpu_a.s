;*********************************************************************************************************
;                                               uC/OS-II
;                                         The Real-Time Kernel
;
;                          (c) Copyright 1992-2003, Jean J. Labrosse, Weston, FL
;                                          All Rights Reserved
;
;                                           
;
; File    : os_cpu_a.s 
; History : 
;  OSCtxSw(), OSIntCtxSw()  OSStartHighRdy() OS_CPU_IRQ_ISR() OSTickISR()
;******************************************************************************************************** */

SRCPND   	EQU  0x4a000000    ; 源未决寄存器 当一个中断发生后，那么相应的位会被置1，表示一个或一类中断发生了。
INTPND   	EQU  0x4a000010    ; 中断未决寄存器 中断发生后，SRCPND中会有位置1，可能好几个（因为同时可能发生几个中断），
							    ;这些中断会由优先级仲裁器选出一个最紧迫的，然后吧把INTPND中相应位置1，所以同一时间只有一位是1。
								;也就是说前面的寄存器置1是表示发生了，只有INTPND置1，CPU才会处理。

rEINTPEND   EQU  0x560000a8
INTOFFSET   EQU  0x4a000014    ;指出IRQ 中断请求源

;ARM工作模式定义
USERMODE    EQU 	0x10
FIQMODE     EQU 	0x11
IRQMODE     EQU 	0x12
SVCMODE     EQU 	0x13
ABORTMODE   EQU 	0x17
UNDEFMODE   EQU 	0x1b
MODEMASK    EQU 	0x1f
NOINT       EQU 	0xc0  ;0x0000 0000 1(Irq)1(Fiq)00 0000 关中断

;*********************************************************************************************************
;                                    EXPORT and EXTERNAL REFERENCES
;*********************************************************************************************************/
	IMPORT  OSRunning
	IMPORT  OSTCBCur
	IMPORT  OSTCBHighRdy
	IMPORT  OSPrioCur
	IMPORT  OSPrioHighRdy
	IMPORT  OSIntNesting
	
			
	IMPORT  OSIntEnter
	IMPORT  OSIntExit
	IMPORT  OSTaskSwHook
	IMPORT  OSTimeTick
	
	IMPORT  HandleEINT0
	

	EXPORT  OSStartHighRdy
	EXPORT  OSCtxSw
	EXPORT  OSTickISR	
	EXPORT  OSIntCtxSw

	EXPORT  OSCPUSaveSR
	EXPORT  OSCPURestoreSR
	
	EXPORT  OS_CPU_IRQ_ISR
	
	 PRESERVE8	
	AREA UCOS_ARM, CODE, READONLY
	
;*********************************************************************************************************
;                                          START MULTITASKING
;                                       void OSStartHighRdy(void) called by OSStart() 
;
; 任务堆栈的组织如下:
;
;							    Entry Point(任务名 PC)				(High memory)
;                               LR(R14)
;                               R12
;                               R11
;                               R10
;                               R9
;                               R8
;                               R7
;                               R6
;                               R5
;                               R4
;                               R3
;                               R2
;                               R1
;                               R0 : argument
; OSTCBHighRdy->OSTCBStkPtr --> CPSR								(Low memory)
;
; Note : OSStartHighRdy() MUST:
;           a) Call OSTaskSwHook() then,
;           b) Set OSRunning to TRUE,
;           c) Switch to the highest priority task.
;
;********************************************************************************************************** */
OSStartHighRdy  
	;----------------------------------------------------------------------------------	
	; OSRunning = TRUE;
	;----------------------------------------------------------------------------------	
	
	MSR     CPSR_cxsf,#SVCMODE|NOINT     ;保持为SVC(管理模式)并关中断 MRS 专门用于状态寄存器和通用寄存器间的数据传输
	
	BL		OSTaskSwHook            ;调用用户定义的 switchhook
	
	LDR		R0, =OSRunning         ;读取OSRunning的地址
	MOV		R1, #1
	STRB 	R1, [R0]        ; OSRunning =TRUE=1

	;----------------------------------------------------------------------------------		
	; 		SP = OSTCBHighRdy->OSTCBStkPtr;此时SP指向栈顶CPSR
	;----------------------------------------------------------------------------------	
	LDR 	R0, =OSTCBHighRdy
	LDR 	R0, [R0]         
	LDR 	SP, [R0]         

	;----------------------------------------------------------------------------------		
	; 恢复任务
	;----------------------------------------------------------------------------------	
	LDMFD 	SP!, {R0}                  ;弹出堆栈的cpsr数据
	MSR 	SPSR_cxsf, R0               ;设置程序的SPSR
	LDMFD 	SP!, {R0-R12, LR, PC}^       ;有^后缀要复制SPSR 到CPSR


;**********************************************************************************************************
;                                PERFORM A CONTEXT SWITCH (From task level)
;                                           void OSCtxSw(void)                 
;
; Note(s): 	   1) Upon entry: 
;              	  OSTCBCur      points to the OS_TCB of the task to suspend
;              	  OSTCBHighRdy  points to the OS_TCB of the task to resume
;
;          	   2) The stack frame of the task to suspend looks as follows:
;                                                   
;                                                   PC                  SP  (High memory)
;				  									LR(R14)					
;           					                    R12
; 			                      			        R11
;           		                			    R10
;                   		           			 	R9
;                           		    			R8
;                               					R7
;                               					R6
;                               					R5
;                               					R4
;                               					R3
;                               					R2
;                               					R1
;                               					R0
; 						OSTCBCur->OSTCBStkPtr ----> CPSR					 (Low memory)
;
;
;          	   3) The stack frame of the task to resume looks as follows:
;
;			  		  								PC				(High memory)
;                                                   LR(R14)	
;			           			                    R12
;           		            			        R11
;                   		        			    R10
;                           		   			 	R9
;                               					R8
;                               					R7
;			                               			R6
;           		                    			R5
;                   		            			R4
;                           		    			R3
;                               					R2
;                               					R1
;			                               			R0
; 					OSTCBHighRdy->OSTCBStkPtr ---->	CPSR				SP	(Low memory)
;
;               步骤：1.保存当前任务的上下文到其的堆栈中
;                      2.恢复高优先级的任务的上下文
;                     3.返回
;
;*********************************************************************************************************/
OSCtxSw
	
	STMFD	SP!, {LR}           ;PC                  ;保存当前任务的上下文
	STMFD	SP!, {R0-R12, LR}   ;R0-R12 LR
	MRS		R0,  CPSR       ;Push CPSR
	STMFD	SP!, {R0}	
		
	;----------------------------------------------------------------------------------
	; 		OSTCBCur->OSTCBStkPtr = SP  OSTCBStkPtr 指向栈顶
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSTCBCur
	LDR		R0, [R0]
	STR		SP, [R0]
	
	;----------------------------------------------------------------------------------		
	;call OSTaskSwHook();
	;---------------------------------------------------------------------------------	
	BL 		OSTaskSwHook

	;----------------------------------------------------------------------------------			
	; OSTCBCur = OSTCBHighRdy;当前任务指向高优先级任务的堆栈
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSTCBHighRdy
	LDR		R1, =OSTCBCur
	LDR		R0, [R0]
	STR		R0, [R1]
	
	;----------------------------------------------------------------------------------		
	; OSPrioCur = OSPrioHighRdy;修改当前任务的优先级
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSPrioHighRdy
	LDR		R1, =OSPrioCur
	LDRB	R0, [R0]
	STRB	R0, [R1]
	
	;----------------------------------------------------------------------------------		
	;  SP=TCBHighRdy->OSTCBStkPtr;设置SP
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSTCBHighRdy
	LDR		R0, [R0]
	LDR		SP, [R0]

	;----------------------------------------------------------------------------------	
	;恢复现场
	;----------------------------------------------------------------------------------	
	LDMFD 	SP!, {R0}		;POP CPSR
	MSR 	SPSR_cxsf, R0
	LDMFD 	SP!, {R0-R12, LR, PC}^	
;*********************************************************************************************************
;                                PERFORM A CONTEXT SWITCH (From an ISR)
;                                        void OSIntCtxSw(void)
;
; Description: 1) 中断任务发生时的任务上下文切换,由于中断会保存现场，故不用手动保存
;
;          	   2) The stack frame of the task to suspend looks as follows:
;
;				  									PC					(High memory)
;                                                   LR(R14)
;           					                    R12
; 			                      			        R11
;           		                			    R10
;                   		           			 	R9
;                           		    			R8
;                               					R7
;                               					R6
;                               					R5
;                               					R4
;                               					R3
;                               					R2
;                               					R1
;                               					R0
;                               					
; 						OSTCBCur->OSTCBStkPtr ----> CPSR					(Low memory)
;
;
;          	   3) The stack frame of the task to resume looks as follows:
;
;			  		  								PC					(High memory)
;                                                   LR(R14)	
;			           			                    R12
;           		            			        R11
;                   		        			    R10
;                           		   			 	R9
;                               					R8
;                               					R7
;			                               			R6
;           		                    			R5
;                   		            			R4
;                           		    			R3
;                               					R2
;                               					R1
;			                               			R0
; 					OSTCBHighRdy->OSTCBStkPtr ---->	CPSR					(Low memory)
;          步骤：      
;                      1.恢复高优先级的任务的上下文
;                      2.返回
;*********************************************************************************************************/
OSIntCtxSw
	;----------------------------------------------------------------------------------		
	; Call OSTaskSwHook();
	;----------------------------------------------------------------------------------	
	BL 		OSTaskSwHook
	
	;----------------------------------------------------------------------------------			
	; OSTCBCur = OSTCBHighRdy;
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSTCBHighRdy
	LDR		R1, =OSTCBCur
	LDR		R0, [R0]
	STR		R0, [R1]
	
	;----------------------------------------------------------------------------------		
	; OSPrioCur = OSPrioHighRdy;
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSPrioHighRdy
	LDR		R1, =OSPrioCur
	LDRB	R0, [R0]
	STRB	R0, [R1]
	
	;----------------------------------------------------------------------------------		
	; 		SP = OSTCBHighRdy->OSTCBStkPtr;
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSTCBHighRdy
	LDR		R0, [R0]
	LDR		SP, [R0]
	
	;----------------------------------------------------------------------------------	
	;恢复现场
	;----------------------------------------------------------------------------------	
	LDMFD 	SP!, {R0}              ;POP CPSR
	MSR 	SPSR_cxsf, R0
	LDMFD 	SP!, {R0-R12, LR, PC}^	
	

	
;*********************************************************************************************************
;                                            TICK HANDLER
;
; Description:  
;     This handles all the Timer0(INT_TIMER0) interrupt which is used to generate the uC/OS-II tick.
;*********************************************************************************************************/

OSTickISR
	MOV     R6,LR	
	MOV 	R1, #1
	MOV		R1, R1, LSL #10		; Timer0 Source Pending Reg.
	LDR 	R0, =SRCPND
	LDR     R2, [R0]
	ORR     R1, R1,R2            ;SRCPND寄存器第10位置1，清除中断请求
	STR 	R1, [R0]

	LDR		R0, =INTPND
	LDR		R1, [R0]
	STR		R1, [R0]		

	;----------------------------------------------------------------------------------		
	; OSTimeTick();
	;----------------------------------------------------------------------------------	
	BL		OSTimeTick
	
  	
	MOV    PC, R6        		; Return 	
	
;----------------------------------------------------------------------------------	
;	中断服务程序过程
; 1、 会把当前的CPSR的值拷贝到SPSR_irq

;2、 把PC的值拷贝到LR_irq

;3、 强制进入IRQ异常模式

;4、 强制进入ARM状态

;5、 禁止IRQ中断

;6、 PC=0X18(或高位地址的0xff18)，跳转到OS_CPU_IRQ_ISR处

;上面这些都是硬件自动完成的。
;----------------------------------------------------------------------------------	
	
OS_CPU_IRQ_ISR 	

	STMFD   SP!, {R1-R3}			; We will use R1-R3 as temporary registers 此时已经是IRQ下的堆栈了
;----------------------------------------------------------------------------
;   R1--SP
;	R2--PC 
;   R3--SPSR
;irqMode use R13_irq(sp) R14_irq(LR) SPSR_irq
;------------------------------------------------------------------------
	MOV     R1, SP
	ADD     SP, SP, #12             ;指回IRQ的堆栈栈底，因为此后不会对IRQ堆栈的直接操作了，要保持R13_irq的值是正确的
	SUB     R2, LR, #4              ;因为中断是发生在一条指令执行完时PC已经指向了当前指令的下两条，故返回地址是LR_irq-#4,这里减4和ARM的3级流水线取指有关系

	MRS     R3, SPSR				; 复制SPSR ( CPSR)
	
   
;*******************************************save context**************************************************

	MSR     CPSR_cxsf, #SVCMODE|NOINT   ;回到管理模式SVC,使sp重新指向SVC的任务的堆栈（R13_SVC）

									; 保存被中断任务的上下文，在原来SVC的堆栈里
									
	STMFD   SP!, {R2}				; 任务 PC  入栈
	STMFD   SP!, {R4-R12, LR}		;  LR,R12-R4入栈
	
	LDMFD   R1!, {R4-R6}			;把放在IRQ堆栈中的 R1-R3 取回来 
	STMFD   SP!, {R4-R6}			; R1-R3 入SVC栈
	STMFD   SP!, {R0}			    ; R0入栈
	
	STMFD   SP!, {R3}				;  CPSR入栈
;*********************************************************************************************************
;             中断服务
	LDR     R0,=OSIntNesting        ;OSIntNesting++ 中断嵌套计数
	LDRB    R1,[R0]
	ADD     R1,R1,#1
	STRB    R1,[R0] 
	
	CMP     R1,#1                   ;if(OSIntNesting==1){
	BNE     OS_CPU_IRQ_ISR_1
	 
	LDR     R4,=OSTCBCur            ;OSTCBHighRdy->OSTCBStkPtr=SP;切换高优先级任务
	LDR     R5,[R4]
	STR     SP,[R5]                 ;}
;*********************************************************************************************************
	
OS_CPU_IRQ_ISR_1
	MSR    CPSR_c,#IRQMODE|NOINT    ;回到IRQ模式，使用IRQ堆栈，处理中断
	
	LDR     R0, =INTOFFSET
    LDR     R0, [R0]
       
    LDR     R1, IRQIsrVect
    MOV     LR, PC                          ; 保存返回地址到LR_irq
    LDR     PC, [R1, R0, LSL #2]            ; Call OS_CPU_IRQ_ISR_handler();   ((R1)+(R0)<<2)->PC ;pc 每次加4
    
    MSR		CPSR_c,#SVCMODE|NOINT   ;回到 SVC mode
    BL 		OSIntExit               ;Call OSIntExit 准备中断退出
    
    LDMFD   SP!,{R4}               ;POP the task''s CPSR 
    MSR		SPSR_cxsf,R4
    LDMFD   SP!,{R0-R12,LR,PC}^	   ;POP new Task''s context

IRQIsrVect DCD HandleEINT0	
    
;*********************************************************************************************************
;                                   CRITICAL SECTION METHOD 3 FUNCTIONS
;
; Description: Disable/Enable interrupts by preserving the state of interrupts.  Generally speaking you
;              would store the state of the interrupt disable flag in the local variable 'cpu_sr' and then
;              disable interrupts.  'cpu_sr' is allocated in all of uC/OS-II''s functions that need to 
;              disable interrupts.  You would restore the interrupt disable state by copying back 'cpu_sr'
;              into the CPU''s status register.
;
; Prototypes : OS_CPU_SR  OSCPUSaveSR(void);
;              void       OSCPURestoreSR(OS_CPU_SR cpu_sr);
;
;
; Note(s)    : 1) These functions are used in general like this:
;
;                 void Task (void *p_arg)
;                 {
;                 #if OS_CRITICAL_METHOD == 3          /* Allocate storage for CPU status register */
;                     OS_CPU_SR  cpu_sr;
;                 #endif
;
;                          :
;                          :
;                     OS_ENTER_CRITICAL();             /* cpu_sr = OSCPUSaveSR();                */
;                          :
;                          :
;                     OS_EXIT_CRITICAL();              /* OSCPURestoreSR(cpu_sr);                */
;                          :
;                          :
;                 }
;
;              2) OSCPUSaveSR() is implemented as recommended by Atmel''s application note:
;
;                    "Disabling Interrupts at Processor Level"
;*********************************************************************************************************
OSCPUSaveSR
	MRS     R0, CPSR				; Set IRQ and FIQ bits in CPSR to disable all interrupts
	ORR     R1, R0, #0xC0
	MSR     CPSR_c, R1
	MRS     R1, CPSR				; Confirm that CPSR contains the proper interrupt disable flags
	AND     R1, R1, #0xC0
	CMP     R1, #0xC0
	BNE     OSCPUSaveSR				; Not properly disabled (try again)
	MOV     PC, LR					; Disabled, return the original CPSR contents in R0

OSCPURestoreSR
	MSR     CPSR_c, R0
	MOV     PC, LR
	        
	END
