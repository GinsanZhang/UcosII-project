#include<2440addr.h>
#include<def.h>
/*nandflash 为AHB总线的设备，当前cpu为400Mhz，AHB分频为100Mhz,10ns
*/
#define TACLS		1	// 1-clk(10ns) 
#define TWRPH0		6	// 3-clk(25ns) (TWRPH0+1)*HCLK=70ns>25
#define TWRPH1		1	// 1-clk(10ns)  //TACLS+TWRPH0+TWRPH1>=50ns

#define NF_MECC_UnLock()    {rNFCONT&=~(1<<5);}
#define NF_MECC_Lock()      {rNFCONT|=(1<<5);}

#define NF_CMD(cmd)			{rNFCMD=cmd;}			//put cmmond
#define NF_ADDR(addr)		{rNFADDR=addr;}		   //put addr
#define NF_nFCE_L()			{rNFCONT&=~(1<<1);}	 //chip select
#define NF_nFCE_H()			{rNFCONT|=(1<<1);}	 //disable chip select
#define NF_RSTECC()			{rNFCONT|=(1<<4);}	  //set ecc
#define NF_RDDATA() 		(rNFDATA)


#define NF_WRDATA(data) 	{rNFDATA=data;}	  //write data

#define NF_WAITRB()    		{while(!(rNFSTAT&(1<<1)));} 
	   						 //wait tWB and check F_RNB pin.
// RnB Signal
#define NF_CLEAR_RB()    	{rNFSTAT |= (1<<2);}	// Have write '1' to clear this bit.
#define NF_DETECT_RB()    	{while(!(rNFSTAT&(1<<2)));}	  // ready/busy detect

void Nand_Reset(){
         volatile int i;
   	 rGPACON = rGPACON |(0x3f<<17); 
	NF_nFCE_L();
	NF_CLEAR_RB();
	for (i=0; i<10; i++);
	NF_CMD(0xFF);	//reset command
	NF_DETECT_RB();
	NF_nFCE_H();
}
void  Nand_Init(void)
{	 rGPACON = rGPACON |(0x3f<<17);  //设置I/O口1 = nFCE 
//1 = nRSTOUT 
//1 = nFRE 
//1 = nFWE 
//1 = ALE 
//1 = CLE 
	rNFCONF = (TACLS<<12)|(TWRPH0<<8)|(TWRPH1<<4)|(0<<0);	
	rNFCONT = (0<<13)|(0<<12)|(0<<10)|(0<<9)|(0<<8)|(1<<6)|(1<<5)|(1<<4)|(1<<1)|(1<<0);
	rNFSTAT = 0;
//	Nand_Reset();
}


//
 void __RdPage2048(U8 *buf,U32 start)
{
	unsigned i;
   //for(i = 0; i < 20; i++);	//调试得出结论需要延时否则读出错误的数据,是因为while((rNFSTAT&(1<<0)))造成的，
   //用while(!(rNFSTAT&(1<<2)));就不需要了
	
	for (i = 0; i < 2048-start; i++) {
		buf[i] =  rNFDATA8;
	}
}
 ////
 int Nand_ReadSectorPage2048(U32 page, U32 start,U8 *buffer)
{  

    Nand_Reset();
 
	NF_nFCE_L();    

	NF_CLEAR_RB();
	NF_CMD(0x00);						// Read command

	NF_ADDR(start&0xff);
	NF_ADDR(start>>8&0x0f);
	NF_ADDR(page&0xff);
	NF_ADDR((page>>8)&0xff);
	NF_ADDR((page>>16)&0xff);
	NF_CMD(0x30);
	
	 
	NF_DETECT_RB();	

    __RdPage2048(buffer,start);

	NF_nFCE_H();    

   	return 1;
}
 int Nand_IsBadBlock(U32 block)
{
    
    U32 	Page;
	U8 		BAD;
   	Page = block << 6;
   	NF_nFCE_L();
    NF_CLEAR_RB();
   	NF_CMD(0x00);
	NF_ADDR(0x00);
	NF_ADDR((2048>>8)&0xff);
    NF_ADDR(Page&0xff);
    NF_ADDR((Page>>8)&0xff);
    NF_ADDR((Page>>16)&0xff);
    NF_CMD(0x30);   
	     
   	NF_DETECT_RB();

   	BAD = rNFDATA8;
             
   	NF_nFCE_H();    

    return BAD != 0xff;
}

int Nand_Copy2SDRAM(U32 ram_base,U32 start,U32 size){
    U32 page_cnt=0;  //page 2048,count amount of page
   	U8 *RAM = (unsigned char *)ram_base;
    U8 page;
	U8 goodpage;
	U8 byte_page_shift = 11; 
	U8 page_block_shift = 6;
	U8 is_zero_start=1;

	if(start!=0) {	  //起始地址不是0，算出读的页数
	   	is_zero_start=0;
		size=size+start;
	  	while(page_cnt*2048<(size)){ page_cnt++;}
	}
	else {
     while(page_cnt*2048<(size)) page_cnt++;
	
	}
	for (page = 0,goodpage=0; page < page_cnt; page ++,goodpage++) {
		// begin of a block
		if (goodpage & ( (1 << page_block_shift) - 1 ) == 0) {
			// found a good block
			for (;;) {
				if (!Nand_IsBadBlock(goodpage>> page_block_shift)) {
					// Is good Block
					break;
				}
				// try next block
				goodpage += (1 << page_block_shift);
			}
		}
		if(is_zero_start==1){
		   Nand_ReadSectorPage2048(goodpage,0,RAM + (page << byte_page_shift ));
		}	
		else{													
		if(page==0){ 
		   Nand_ReadSectorPage2048(goodpage,start,RAM+ (page << byte_page_shift ));		     
		}
		else 
		Nand_ReadSectorPage2048(goodpage,0,RAM +(2048-start)+((page-1) << byte_page_shift ));
		
	   
		}
	
	}


	return 0;

} 
