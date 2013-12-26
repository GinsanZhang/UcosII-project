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

SRCPND   	EQU  0x4a000000    ; Դδ���Ĵ��� ��һ���жϷ�������ô��Ӧ��λ�ᱻ��1����ʾһ����һ���жϷ����ˡ�
INTPND   	EQU  0x4a000010    ; �ж�δ���Ĵ��� �жϷ�����SRCPND�л���λ��1�����ܺü�������Ϊͬʱ���ܷ��������жϣ���
							    ;��Щ�жϻ������ȼ��ٲ���ѡ��һ������ȵģ�Ȼ��ɰ�INTPND����Ӧλ��1������ͬһʱ��ֻ��һλ��1��
								;Ҳ����˵ǰ��ļĴ�����1�Ǳ�ʾ�����ˣ�ֻ��INTPND��1��CPU�Żᴦ��

rEINTPEND   EQU  0x560000a8
INTOFFSET   EQU  0x4a000014    ;ָ��IRQ �ж�����Դ

;ARM����ģʽ����
USERMODE    EQU 	0x10
FIQMODE     EQU 	0x11
IRQMODE     EQU 	0x12
SVCMODE     EQU 	0x13
ABORTMODE   EQU 	0x17
UNDEFMODE   EQU 	0x1b
MODEMASK    EQU 	0x1f
NOINT       EQU 	0xc0  ;0x0000 0000 1(Irq)1(Fiq)00 0000 ���ж�

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
; �����ջ����֯����:
;
;							    Entry Point(������ PC)				(High memory)
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
	
	MSR     CPSR_cxsf,#SVCMODE|NOINT     ;����ΪSVC(����ģʽ)�����ж� MRS ר������״̬�Ĵ�����ͨ�üĴ���������ݴ���
	
	BL		OSTaskSwHook            ;�����û������ switchhook
	
	LDR		R0, =OSRunning         ;��ȡOSRunning�ĵ�ַ
	MOV		R1, #1
	STRB 	R1, [R0]        ; OSRunning =TRUE=1

	;----------------------------------------------------------------------------------		
	; 		SP = OSTCBHighRdy->OSTCBStkPtr;��ʱSPָ��ջ��CPSR
	;----------------------------------------------------------------------------------	
	LDR 	R0, =OSTCBHighRdy
	LDR 	R0, [R0]         
	LDR 	SP, [R0]         

	;----------------------------------------------------------------------------------		
	; �ָ�����
	;----------------------------------------------------------------------------------	
	LDMFD 	SP!, {R0}                  ;������ջ��cpsr����
	MSR 	SPSR_cxsf, R0               ;���ó����SPSR
	LDMFD 	SP!, {R0-R12, LR, PC}^       ;��^��׺Ҫ����SPSR ��CPSR


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
;               ���裺1.���浱ǰ����������ĵ���Ķ�ջ��
;                      2.�ָ������ȼ��������������
;                     3.����
;
;*********************************************************************************************************/
OSCtxSw
	
	STMFD	SP!, {LR}           ;PC                  ;���浱ǰ�����������
	STMFD	SP!, {R0-R12, LR}   ;R0-R12 LR
	MRS		R0,  CPSR       ;Push CPSR
	STMFD	SP!, {R0}	
		
	;----------------------------------------------------------------------------------
	; 		OSTCBCur->OSTCBStkPtr = SP  OSTCBStkPtr ָ��ջ��
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSTCBCur
	LDR		R0, [R0]
	STR		SP, [R0]
	
	;----------------------------------------------------------------------------------		
	;call OSTaskSwHook();
	;---------------------------------------------------------------------------------	
	BL 		OSTaskSwHook

	;----------------------------------------------------------------------------------			
	; OSTCBCur = OSTCBHighRdy;��ǰ����ָ������ȼ�����Ķ�ջ
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSTCBHighRdy
	LDR		R1, =OSTCBCur
	LDR		R0, [R0]
	STR		R0, [R1]
	
	;----------------------------------------------------------------------------------		
	; OSPrioCur = OSPrioHighRdy;�޸ĵ�ǰ��������ȼ�
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSPrioHighRdy
	LDR		R1, =OSPrioCur
	LDRB	R0, [R0]
	STRB	R0, [R1]
	
	;----------------------------------------------------------------------------------		
	;  SP=TCBHighRdy->OSTCBStkPtr;����SP
	;----------------------------------------------------------------------------------		
	LDR		R0, =OSTCBHighRdy
	LDR		R0, [R0]
	LDR		SP, [R0]

	;----------------------------------------------------------------------------------	
	;�ָ��ֳ�
	;----------------------------------------------------------------------------------	
	LDMFD 	SP!, {R0}		;POP CPSR
	MSR 	SPSR_cxsf, R0
	LDMFD 	SP!, {R0-R12, LR, PC}^	
;*********************************************************************************************************
;                                PERFORM A CONTEXT SWITCH (From an ISR)
;                                        void OSIntCtxSw(void)
;
; Description: 1) �ж�������ʱ�������������л�,�����жϻᱣ���ֳ����ʲ����ֶ�����
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
;          ���裺      
;                      1.�ָ������ȼ��������������
;                      2.����
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
	;�ָ��ֳ�
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
	ORR     R1, R1,R2            ;SRCPND�Ĵ�����10λ��1������ж�����
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
;	�жϷ���������
; 1�� ��ѵ�ǰ��CPSR��ֵ������SPSR_irq

;2�� ��PC��ֵ������LR_irq

;3�� ǿ�ƽ���IRQ�쳣ģʽ

;4�� ǿ�ƽ���ARM״̬

;5�� ��ֹIRQ�ж�

;6�� PC=0X18(���λ��ַ��0xff18)����ת��OS_CPU_IRQ_ISR��

;������Щ����Ӳ���Զ���ɵġ�
;----------------------------------------------------------------------------------	
	
OS_CPU_IRQ_ISR 	

	STMFD   SP!, {R1-R3}			; We will use R1-R3 as temporary registers ��ʱ�Ѿ���IRQ�µĶ�ջ��
;----------------------------------------------------------------------------
;   R1--SP
;	R2--PC 
;   R3--SPSR
;irqMode use R13_irq(sp) R14_irq(LR) SPSR_irq
;------------------------------------------------------------------------
	MOV     R1, SP
	ADD     SP, SP, #12             ;ָ��IRQ�Ķ�ջջ�ף���Ϊ�˺󲻻��IRQ��ջ��ֱ�Ӳ����ˣ�Ҫ����R13_irq��ֵ����ȷ��
	SUB     R2, LR, #4              ;��Ϊ�ж��Ƿ�����һ��ָ��ִ����ʱPC�Ѿ�ָ���˵�ǰָ������������ʷ��ص�ַ��LR_irq-#4,�����4��ARM��3����ˮ��ȡָ�й�ϵ

	MRS     R3, SPSR				; ����SPSR ( CPSR)
	
   
;*******************************************save context**************************************************

	MSR     CPSR_cxsf, #SVCMODE|NOINT   ;�ص�����ģʽSVC,ʹsp����ָ��SVC������Ķ�ջ��R13_SVC��

									; ���汻�ж�����������ģ���ԭ��SVC�Ķ�ջ��
									
	STMFD   SP!, {R2}				; ���� PC  ��ջ
	STMFD   SP!, {R4-R12, LR}		;  LR,R12-R4��ջ
	
	LDMFD   R1!, {R4-R6}			;�ѷ���IRQ��ջ�е� R1-R3 ȡ���� 
	STMFD   SP!, {R4-R6}			; R1-R3 ��SVCջ
	STMFD   SP!, {R0}			    ; R0��ջ
	
	STMFD   SP!, {R3}				;  CPSR��ջ
;*********************************************************************************************************
;             �жϷ���
	LDR     R0,=OSIntNesting        ;OSIntNesting++ �ж�Ƕ�׼���
	LDRB    R1,[R0]
	ADD     R1,R1,#1
	STRB    R1,[R0] 
	
	CMP     R1,#1                   ;if(OSIntNesting==1){
	BNE     OS_CPU_IRQ_ISR_1
	 
	LDR     R4,=OSTCBCur            ;OSTCBHighRdy->OSTCBStkPtr=SP;�л������ȼ�����
	LDR     R5,[R4]
	STR     SP,[R5]                 ;}
;*********************************************************************************************************
	
OS_CPU_IRQ_ISR_1
	MSR    CPSR_c,#IRQMODE|NOINT    ;�ص�IRQģʽ��ʹ��IRQ��ջ�������ж�
	
	LDR     R0, =INTOFFSET
    LDR     R0, [R0]
       
    LDR     R1, IRQIsrVect
    MOV     LR, PC                          ; ���淵�ص�ַ��LR_irq
    LDR     PC, [R1, R0, LSL #2]            ; Call OS_CPU_IRQ_ISR_handler();   ((R1)+(R0)<<2)->PC ;pc ÿ�μ�4
    
    MSR		CPSR_c,#SVCMODE|NOINT   ;�ص� SVC mode
    BL 		OSIntExit               ;Call OSIntExit ׼���ж��˳�
    
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
