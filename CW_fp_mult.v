/* ===============================================================================
Copyright (c) 2022 by Cadence Design Systems Inc.  ALL RIGHTS
RESERVED.  These coded instructions, statements, and computer
programs are the copyrighted works and confidential proprietary
information of Cadence Design Systems Inc. They may not be modified,
copied, reproduced, distributed, or disclosed to third parties in
any manner, medium, or form, in whole or in part, without the prior
written consent of Cadence Design Systems Inc.
==================================================================================

Version and Release Control Information:
  
File Name           : CW_fp_mult.v
File Revision       : V1.1
Author              :                                  Date :           
Modified By         : Swapnil Vairale                  Date : 10/11/2022
Comments            : sim-syn model alignment, code reformatting 
Release Information : Genus 23.10 
  
----------------------------------------------------------------------------
    Module         : CW_fp_mult
    Abstract       : Floating Point Multiplier

    Pin Name         Width                        Direction   Function
-----------------------------------------------------------------------
    a                sig_width+exp_width+1 bits   Input       Input data
    b                sig_width+exp_width+1 bits   Input       Input data
    rnd              3 bits                       Input       Rounding mode
    status           8 bits                       Output      Status flags
    z                sig_width+exp_width+1 bits   Output      a * b

-----------------------------------------------------------------------

    Parameter           Values          Description
-----------------------------------------------------------------------
    sig_width           2 to 112 bits  Word length of fraction field of floating-point numbers a,b and z.
    exp_width           3 to 15 bits   Word length of biased exponent of floating point numbers a,b and z.
    ieee_compliance     0,1 or 3       0: honors neither Denormals nor NaNs 
                                       1: honors Denormals & partially honors NaNs 
                                       3: honors Denormals &  honors NaNs
    arch                0 or 1         0: Only arch for ieee_compliance=1/3 & Area efficient implementation for ieee_compliance=0 
                                       1: Improves timing at the cost of area only allowed when ieee_compliance=0
    return_signed_nans  0 or 1         Forces the sign bit of z to be the XOR of the sign bits of a and b.    
                                       This means the sign of the output is consistent with the signs of the inputs even when the results is NaN.
-----------------------------------------------------------------------*/

module CW_fp_mult__builtin (
  a,
  b,
  rnd,
  status,
  z);

  // cwd ip protection false

  //----------------------------------------
  // Parameter
  //----------------------------------------
  parameter sig_width          = 23;
  parameter exp_width          = 8;
  parameter ieee_compliance    = 1;
  parameter arch               = 0; // New architecture for fastest non-compliant component
  parameter return_signed_nans = 0; // Request from TI

  //----------------------------------------
  // Inputs 
  //----------------------------------------
  //@{
  input   [sig_width+exp_width:0]   a   ;
  input   [sig_width+exp_width:0]   b   ;
  input   [2:0]                     rnd ;

  //----------------------------------------
  // Output 
  //----------------------------------------
  output  [7:0]                     status;
  output  [sig_width+exp_width:0]   z;
  //@}

  //----------------------------------------
  // Localparam
  //----------------------------------------
  localparam tiny_fix           = 1; // Existing component has a bug

  //----------------------------------------------------------------------
  // cadence translate_off
  // synopsys translate_off
  //----------------------------------------------------------------------
initial begin : parameter_check
    integer err_flag;
    err_flag = 0;
    if ( !( (ieee_compliance == 0) || (ieee_compliance == 1) || (ieee_compliance == 3) ) ) begin
      err_flag = 1;
      $display("ERROR: %m :\n  Invalid value (%d) for parameter ieee_compliance (valid range: 0, 1 or 3)", ieee_compliance );
    end
    if ( (arch < 0) || (arch > 1) ) begin
      err_flag = 1;
      $display("ERROR: %m :\n  Invalid value (%d) for parameter arch (valid range: 0 or 1)", arch );
    end
    if ( (arch == 1) && (ieee_compliance != 0) ) begin
      err_flag = 1;
      $display("ERROR: %m :\n  Invalid value (%d) for parameter arch .Can not set arch == 1 when ieee_compliance != 0", arch );
    end
    if ( (return_signed_nans < 0) || (return_signed_nans > 1) ) begin
      err_flag = 1;
      $display("ERROR: %m :\n  Invalid value (%d) for parameter return_signed_nans (valid range: 0 or 1)", return_signed_nans );
    end
    if ((sig_width < 2) || (sig_width > 112) ) begin
      err_flag = 1;
      $display("ERROR: %m :\n  Invalid value (%d) for parameter sig_width (valid range: 2 to 112)", sig_width );
    end
    if ((exp_width < 3) || (exp_width > 15)) begin
      err_flag = 1;
      $display("ERROR: %m :\n  Invalid value (%d) for parameter exp_width (valid range: 3 to 15)", exp_width );
    end
    if ( err_flag == 1) begin
      $display("%m :\n  Simulation stopped due to invalid parameter value(s)");
      $finish;
    end
  end
  //----------------------------------------------------------------------
  // synopsys translate_on
  // cadence translate_on
  //----------------------------------------------------------------------

  if (arch == 1 && ieee_compliance == 0) begin : arch_0_ieee_0
    // Then instantiate the new, faster architecture
    CW_fp_mult__non_compliant #(
      .sig_width          (sig_width),
      .exp_width          (exp_width),
      .return_signed_nans (return_signed_nans)
    ) CW_fp_mult__non_compliant_inst(
      .a      (a)   ,
      .b      (b)   ,
      .rnd    (rnd) ,
      .z      (z)   ,
      .status (status)
    );
     end
  else if (arch == 0 && ieee_compliance > 0) begin : arch_0_ieee_n0
    // Then instantiate the new, faster architecture
    CW_fp_mult__compliant #(
      .sig_width          (sig_width),
      .exp_width          (exp_width),
      .ieee_compliance    (ieee_compliance),
      .return_signed_nans (return_signed_nans)
    ) CW_fp_mult__compliant_inst (
      .a      (a)   ,
      .b      (b)   ,
      .rnd    (rnd) ,
      .z      (z)   ,
      .status (status)
    );
  end
  else if (ieee_compliance > 0) begin : ieee_n0

    //----------------------------------------
    // Localparam
    //----------------------------------------
    //! computed parameters \todo put these into a class so that we can share across components
    //@{
    localparam [exp_width-1:0]         E_Inf       = {exp_width{1'b1}};
    localparam [exp_width-1:0]         E_Zero      = {exp_width{1'b0}};
    localparam [exp_width-1:0]         E_MinNorm   = {{(exp_width-1){1'b0}},1'b1};
    localparam [exp_width-1:0]         E_MaxNorm   = {{(exp_width-1){1'b1}},1'b0};
    localparam [sig_width-1:0]         M_Zero      = {sig_width{1'b0}};
    localparam [sig_width-1:0]         M_MaxNorm   = ~M_Zero;

    localparam [sig_width+exp_width:0] CW_NaN      = (ieee_compliance == 3) ?
                                                     {1'b0,E_Inf,1'b1,{(sig_width-1){1'b0}}} :
                                                     {1'b0,E_Inf,{(sig_width-1){1'b0}},1'b1};
    localparam [sig_width+exp_width:0] pos_MinNorm = {1'b0,E_MinNorm, M_Zero};
    localparam [sig_width+exp_width:0] neg_MinNorm = {1'b1,E_MinNorm, M_Zero};
    localparam [sig_width+exp_width:0] pos_MaxNorm = {1'b0,E_MaxNorm,~M_Zero};
    localparam [sig_width+exp_width:0] neg_MaxNorm = {1'b1,E_MaxNorm,~M_Zero};
       localparam [sig_width+exp_width:0] pos_Inf     = {1'b0,E_Inf    , M_Zero};
    localparam [sig_width+exp_width:0] neg_Inf     = {1'b1,E_Inf    , M_Zero};
    localparam [sig_width+exp_width:0] pos_Zero    = {1'b0,E_Zero   , M_Zero};
    localparam [sig_width+exp_width:0] neg_Zero    = {1'b1,E_Zero   , M_Zero};
    localparam [exp_width-1:0]         bias        = {1'b0,{(exp_width-1){1'b1}}};
    //@}

    //! The size of the fixed point result
    //@{
    localparam fixed_point_product_width = 2 + 2*sig_width; //[2.(2*sig_width)]
    //@}
    localparam lzc_width = $clog2(sig_width+1);
    /* F_exp needs to be wide enough to handle the intermediate result of:
    *  a_exp + b_exp - bias +fixed_point_product[fixed_point_product_width-1] - $lead0(a_sig) - $lead0(b_sig)
    *  Grouping the first four and the second two together that looks something like:
    *  [0 + 0 - bias + 0, 2*bias + 2*bias - bias + 1] + [-(sig_width-1) -(sig_width-1), 0]
    *  [-bias, 3*bias+1] + [2 - 2*sig_width, 0]
    *  [2-2*sig_width-bias, 3*bias+1]
    *  The upper bound => we need at least an S[ew+2]
    *  The lower bound => we need at least an S[1+clog2(bias+2*sig_width-2)]
    *  i.e. we need an S[$max(ew+2,1+$clog2(bias+2*sig_width-2)]
    *  Obviosuly if we don't have the leading zero offset shenanigans to worry about then we just need
    *  an S[ew+2] */
    localparam F_exp_width_upper = (ieee_compliance == 0) ? 0 : 1+$clog2(bias+2*sig_width-2);
    localparam F_exp_width_lower = exp_width+2;
    localparam F_exp_width       = (F_exp_width_upper > F_exp_width_lower)
                                   ? F_exp_width_upper : F_exp_width_lower;

    // The top two bits are for the overflow, if we round up and for the "hidden" 1.
    localparam F_sig_width          = sig_width + 2; //U[2.sig_width]

    /* How far is it worth shifting to the right assuming that the "hidden" 1 may be in either of the
    *  first two bits?
    *   * ieee_compliance==1.  Once you've moved the "hidden" 1 into the first bit past the guard bit,
    *     any further shifting doesn't affect the value of sig, guard, or sticky.
    *   * ieee_compliance==0.  There's no point shifting more than 3 places because we're going to
    *     flush denormals after rounding to either Zero or MinNorm.  Either way, we only need the edge
    *     case where a denormal after rouding could become normal.  3 places to the right guarantees
    *     that F_sig = 00.0xxxx... which can at most round to 00.100000.. which is still denormal and
    *     will be flushed.  Further shifting is pointless. */
 localparam max_right_shift      = (ieee_compliance > 0)
                                      ? sig_width + 3
                                      : 3;

    // The bits that will be shifted out, the guard, followed by the sticky bits
    localparam F_sig_extra_width    = 2 + (max_right_shift - 1); //U[2.sig_width]

    // Size of the storage we need for the right shift for denormailisation.
    localparam right_shift_width    = $clog2(max_right_shift+1);
    // This is the exponent that shifts the leading one into the bit past the guard bit.
    // Shifting further cannot change the rounding.
    localparam signed E_Min     = E_MinNorm - (max_right_shift - 1);
    localparam signed E_Min_dec = E_Min - 1;

    localparam max_fpp_lzc = 2 + 2 * sig_width;
    localparam fpp_lzc_width = $clog2(max_fpp_lzc+1);

    // bias >= sig_width + 2 guarantees that, for denorm x denorm, we're going to be shifting the
    // entirety of fpp into sticky bits so we can shift back by any amount that doesn't shift out
    // leading ones.  That means we don't need to add the two LZCs and we can reduce the shifter
    // width significantly.
    localparam max_left_shift   = bias < sig_width + 2 ? max_fpp_lzc : sig_width; //sig_width?  I think I can tighten this for better ppa
    localparam left_shift_width = $clog2(max_left_shift+1);
    localparam wi               = sig_width;
    localparam wr               = $clog2(wi+1);

    //! decoded inputs
    //@{
    wire                              a_sign     , b_sign;
    wire    [exp_width-1:0]           a_exp      , b_exp;
    wire    [sig_width-1:0]           a_sig      , b_sig;
    //@}

    //! functions of the a/b inputs
    //@{
    wire                              a_E_Inf    , b_E_Inf ;    //!< a/b has an "Inf" exponent
    wire                              a_E_Zero   , b_E_Zero ;   //!< a/b has a "Zero" exponent
    wire                              a_M_Zero   , b_M_Zero;    //!< a/b has a "Zero" mantissa
    wire                              a_NaN      , b_NaN;       //!< a/b is NaN
    wire                              a_sNaN     , b_sNaN;
    wire                              a_Denorm   , b_Denorm;    //!< a/b is Denorm
    wire                              a_Inf      , b_Inf;       //!< a/b is Inf
    wire                              a_Zero     , b_Zero;      //!< a/b is Zero

    //@}
    
    reg [fixed_point_product_width-1:0] fixed_point_product;
    reg [sig_width:0]                   a_sig_norm , b_sig_norm;  //!< a/b significand after normalization
    reg [lzc_width-1:0]                 a_LZC, b_LZC;

    //@{
    reg                                 ZERO;
    reg                                 INFINITY;
    reg                                 INVALID;
    reg                                 TINY;
    reg                                 HUGE;
    reg                                 INEXACT;
    reg                                 DIVZERO;
    reg [sig_width+exp_width:0]         z_out;
    //@}

    // F from the spec
    reg                                 F_sign;
    reg                                 F_NaN;
    reg                                 Signal_NaN;
    reg                                 F_Zero;
    reg                                 F_Inf;
    reg                                 F_Special;
    reg signed [F_exp_width-1:0]        F_exp, F_exp_round;
    reg signed [F_exp_width-1:0]        F_exp_pre_norm, F_exp_pre_norm_inc;
    reg        [F_sig_width-1:0]        F_sig, F_sig_round;
    reg        [F_sig_extra_width-1:0]  F_sig_extra;
    reg                                 F_huge, F_huge_round, F_tiny, F_tiny_round;

    // Z from the spec
    reg                                 Z_sign;
    reg                                 Z_Zero;
    reg                                 Z_Inf;

    // The right shift for denormalisation.
    reg [right_shift_width-1:0] right_shift;

    // The guard and sticky bits for the rounding of F->F'
    reg                                 guard, sticky ;
    reg [left_shift_width-1:0]          left_shift    ;
    reg [fpp_lzc_width-1:0]             fpp_lzc       ;
    reg [fixed_point_product_width-1:0] fpp_pre_shift ;

    //! bring in the rounding tools
    function automatic round_up;
      input [2:0] rnd;
      input sign;
      input odd;
      input guard;
      input sticky;
      begin
        casez(rnd)
          3'b000 : round_up = guard & (sticky | odd)   ; //RTE
          3'b001 : round_up = 1'b0                     ; //RTZ
          3'bz10 : round_up = ~sign & (guard | sticky) ; //RTPI
          3'bz11 : round_up = sign & (guard | sticky)  ; //RTNI
          3'b100 : round_up = guard & (sticky | ~sign) ; //RTU ? round to nearest, up
          3'b101 : round_up = guard | sticky           ; //RAZ
        endcase
      end
    endfunction

    function automatic huge_is_inf;
      input [2:0] rnd;
      input sign;
      begin
        casez(rnd)
          3'b000 : huge_is_inf = 1'b1  ; //RTE
          3'b001 : huge_is_inf = 1'b0  ; //RTZ
          3'bz10 : huge_is_inf = ~sign ; //RTPI
          3'bz11 : huge_is_inf = sign  ; //RTNI
          3'b100 : huge_is_inf = 1'b1  ; //RTU
          3'b101 : huge_is_inf = 1'b1  ; //RAZ
        endcase
      end
    endfunction

    function automatic tiny_is_zero;
      input [2:0] rnd;
      input sign;
      begin
        casez(rnd)
          3'b000 : tiny_is_zero = 1'b1  ; //RTE
          3'b001 : tiny_is_zero = 1'b1  ; //RTZ
          3'bz10 : tiny_is_zero = sign  ; //RTPI
          3'bz11 : tiny_is_zero = ~sign ; //RTNI
          3'b100 : tiny_is_zero = 1'b1  ; //RTU
          3'b101 : tiny_is_zero = 1'b0  ; //RAZ
        endcase
      end
    endfunction

    //! Decode the a/b inputs
    //@{
    assign {a_sign , a_exp  , a_sig} = a;
    assign {b_sign , b_exp  , b_sig} = b;

    assign {a_E_Inf  , b_E_Inf  } = {a_exp==E_Inf           , b_exp==E_Inf           };
    assign {a_E_Zero , b_E_Zero } = {a_exp==E_Zero          , b_exp==E_Zero          };
    assign {a_M_Zero , b_M_Zero } = {a_sig==M_Zero          , b_sig==M_Zero          };
    assign {a_NaN    , b_NaN    } = (ieee_compliance==0)
                                    ? {1'b0                   , 1'b0                   }
                                    : {a_E_Inf  & ~a_M_Zero   , b_E_Inf  & ~b_M_Zero   };
    assign {a_sNaN   , b_sNaN   } = (ieee_compliance==3)
                                    ? {a_NaN & ~a[sig_width-1], b_NaN & ~b[sig_width-1]}
                                    : {a_NaN                  , b_NaN                  };
    assign {a_Denorm , b_Denorm } = (ieee_compliance==0)
                                    ? {1'b0                   , 1'b0                   }
                                    : {a_E_Zero & ~a_M_Zero   , b_E_Zero & ~b_M_Zero   };
    assign {a_Inf    , b_Inf    } = (ieee_compliance==0)
                                    ? {a_E_Inf                , b_E_Inf                }
                                    : {a_E_Inf  & a_M_Zero    , b_E_Inf  & b_M_Zero    };
    assign {a_Zero   , b_Zero   } = (ieee_compliance==0)
                                    ? {a_E_Zero               , b_E_Zero               }
                                    : {a_E_Zero & a_M_Zero    , b_E_Zero & b_M_Zero    };

    //@}

    //! Normalize the inputs
    //@{
    always @(*) begin
      if (ieee_compliance == 0) begin
        {a_sig_norm, b_sig_norm}  =  {1'b1, a_sig, 1'b1, b_sig};
        {a_LZC, b_LZC}            =  {{lzc_width{1'b0}}, {lzc_width{1'b0}}};
      end
      else begin
        a_LZC                     =  a_Denorm ? $lead0(a_sig) : {lzc_width{1'b0}};
        b_LZC                     =  b_Denorm ? $lead0(b_sig) : {lzc_width{1'b0}};
        {a_sig_norm, b_sig_norm}  =  {~a_Denorm,a_sig,~b_Denorm,b_sig};
      end
    end
    //@}

    // guts of the floating point computation
 always @(*) begin

      {F_sign, F_Zero, F_Inf, F_NaN} = {
        a_sign ^ b_sign                                     ,
        b_Zero & ~a_Inf & ~a_NaN | a_Zero & ~b_Inf & ~b_NaN ,
        b_Inf & ~a_Zero & ~a_NaN | a_Inf & ~b_Zero & ~b_NaN ,
        a_NaN | b_NaN | (b_Inf & a_Zero) | (b_Zero & a_Inf)
      };
      Signal_NaN         = a_sNaN | b_sNaN | b_Inf & a_Zero | b_Zero & a_Inf;
      F_Special          = F_Zero | F_Inf | F_NaN;
      F_exp_pre_norm     = a_exp + b_exp - bias - b_LZC - a_LZC;
      F_exp_pre_norm_inc = a_exp + b_exp - bias - b_LZC - a_LZC +1;

      //! Do the fixed point multiplication
      //@{
      if ((ieee_compliance > 0) && (bias < sig_width +2)) begin
        fpp_lzc = a_LZC + b_LZC + a_Denorm + b_Denorm;
        //left_shift = a_Denorm ? a_LZC : b_LZC;
        left_shift = fpp_lzc > max_left_shift ? max_left_shift : fpp_lzc;
        fpp_pre_shift = a_sig_norm * b_sig_norm;
        fixed_point_product = fpp_pre_shift << left_shift;
      end
      else if ((ieee_compliance > 0) && (bias >= sig_width+2)) begin
        left_shift = a_Denorm ? a_Denorm + a_LZC : b_Denorm + b_LZC;
        fpp_pre_shift = a_sig_norm * b_sig_norm;
        fixed_point_product = fpp_pre_shift << left_shift;
      end
      else begin
        fixed_point_product = a_sig_norm * b_sig_norm;
      end
      //@}

      F_exp = fixed_point_product[fixed_point_product_width-1]
              ? F_exp_pre_norm_inc
              : F_exp_pre_norm;

      //!!!I'M HERE!!!

      //NB F_exp, F_sig, F_huge, F_tiny (and F_exp_round etc.) have NO meaning if F_NaN|F_Zero|F_Inf
      //NB: never rely on F_sig (or anything computed from it) to be correct if F_huge
      //NB: F_huge |-> ~F_tiny
      {F_huge, F_tiny} = {~F_Special & (F_exp > $signed({1'b0, E_MaxNorm})),
                          ~F_Special & (F_exp < $signed({1'b0, E_MinNorm}))};

      /*NB: This used to be: casez ({F_tiny, F_exp < E_Min}), however:
      *     1.      (F_exp_pre_norm_inc <= E_Min)
      *        <==> (F_exp_pre_norm < E_Min)
      *        <==> (F_exp < E_Min) | fpp[msb] & (F_exp == E_Min)
      *        When fpp[msb] & (F_exp == E_Min), right_shift computed according to the last two branches
      *         (i)   E_MinNorm - F_exp_pre_norm
      *             = E_MinNorm - F_exp -1
      *             = E_MinNorm - E_Min -1
      *             = E_MinNorm - (E_MinNorm - max_right_shift - 1) -1
      *             = max_right_shift
      *        (ii)   max_right_shift
      * 
      *     2.      (F_exp_pre_norm_inc <= E_MinNorm)
      *        <==> F_exp_pre_norm < E_MinNorm
      *        <==> (F_exp < E_MinNorm) | fpp[msb] & (F_exp == E_MinNorm)
      *        <==> F_tiny | fpp[msb] & (F_exp == E_MinNorm)
      *        When fpp[msb] & (F_exp == E_MinNorm), right_shift computed according to the first two
      *        branches:
      *         (i)   1
      *        (ii)   E_MinNorm - (F_exp - 1)
      *             = E_MinNorm - (E_MinNorm - 1)
      *              *             = 1
        
      *   $display("{F_exp_pre_norm_inc <= E_MinNorm, F_exp_pre_norm_inc <= E_Min}=%b",
      *            {F_exp_pre_norm_inc <= $signed(E_MinNorm), F_exp_pre_norm_inc <= E_Min}); */

      casez ({F_exp_pre_norm_inc <= $signed(E_MinNorm), F_exp_pre_norm_inc <= E_Min})
        3'b0z: right_shift = fixed_point_product[fixed_point_product_width-1];
        3'b10: right_shift = $signed(E_MinNorm) - F_exp_pre_norm;
        3'b11: right_shift = (max_right_shift - 1) + fixed_point_product[fixed_point_product_width-1];
      endcase

      {F_sig, F_sig_extra} = {fixed_point_product[fixed_point_product_width-1:fixed_point_product_width-F_sig_width],
                              fixed_point_product[fixed_point_product_width-F_sig_width-1],
                              {(F_sig_extra_width-1){1'b0}}} >> right_shift;

      {guard, sticky} = {F_sig_extra[F_sig_extra_width-1],
                        |F_sig_extra[F_sig_extra_width-2:0] | (|fixed_point_product[fixed_point_product_width-F_sig_width-2:0])};

      F_sig_round = F_sig + round_up(rnd, F_sign, F_sig[0], guard, sticky);

      F_exp_round = F_exp + (~F_huge & F_sig_round[F_sig_width-1] | F_tiny & F_sig_round[F_sig_width-2]);

      F_huge_round = F_huge | ~F_Special & (F_exp_round == (E_MaxNorm+1));
      F_tiny_round = F_tiny & ~F_Special & ~(F_exp_round == E_MinNorm);

      Z_Zero = F_Zero
               | ((ieee_compliance > 0) ? ~F_NaN & ~F_Inf & ~F_huge_round & (F_sig_round == {F_sig_width{1'b0}})
                 : (F_tiny_round & tiny_is_zero(rnd, F_sign)));
      Z_Inf  = F_Inf
               | ((ieee_compliance > 0) ? F_huge_round & huge_is_inf(rnd, F_sign)
                 : F_NaN | F_huge_round & huge_is_inf(rnd, F_sign));
      Z_sign = return_signed_nans ? F_sign : F_sign & ~F_NaN;

      ZERO      = Z_Zero                                                                                      ;
      INFINITY  = Z_Inf                                                                                       ;
      INVALID   = Signal_NaN                                                                                  ;
      TINY      = ~F_Special & (tiny_fix ? F_tiny : F_tiny_round) & (!(ieee_compliance > 0) | sticky | guard) ;
      HUGE      = F_huge_round                                                                                ;
      INEXACT   = ~F_Special & (sticky | guard | F_huge_round | !(ieee_compliance > 0) & F_tiny_round)        ;
      DIVZERO   = 1'b0                                                                                        ;

  // sign bit out
      z_out[sig_width+exp_width] = Z_sign;

      // exponent out
      if (ieee_compliance == 0) begin
        casez({Z_Inf, F_huge_round, Z_Zero, F_tiny_round})
          4'b1zzz: z_out[sig_width+exp_width-1:sig_width] = E_Inf                      ;
          4'b01zz: z_out[sig_width+exp_width-1:sig_width] = E_MaxNorm                  ;
          4'b001z: z_out[sig_width+exp_width-1:sig_width] = E_Zero                     ;
          4'b0001: z_out[sig_width+exp_width-1:sig_width] = E_MinNorm                  ;
          4'b0000: z_out[sig_width+exp_width-1:sig_width] = F_exp_round[exp_width-1:0] ;
        endcase
      end
      else begin
        casez({F_NaN, Z_Inf, F_huge_round, Z_Zero | F_tiny_round})
          4'b1zzz: z_out[sig_width+exp_width-1:sig_width] = CW_NaN[sig_width+exp_width-1:sig_width] ;
          4'b01zz: z_out[sig_width+exp_width-1:sig_width] = E_Inf                                   ;
          4'b001z: z_out[sig_width+exp_width-1:sig_width] = E_MaxNorm                               ;
          4'b0001: z_out[sig_width+exp_width-1:sig_width] = E_Zero                                  ;
          4'b0000: z_out[sig_width+exp_width-1:sig_width] = F_exp_round[exp_width-1:0]              ;
        endcase
      end

      // significand out
      if (ieee_compliance == 0) begin
        casez({Z_Inf | Z_Zero | F_tiny_round, F_huge_round})
          2'b1z: z_out[sig_width-1:0] = M_Zero;
          2'b01: z_out[sig_width-1:0] = M_MaxNorm;
          2'b00: z_out[sig_width-1:0] = F_sig_round[sig_width-1:0];
        endcase
      end
      else begin
        casez({F_NaN, Z_Inf | Z_Zero, F_huge_round})
          3'b1zz: z_out[sig_width-1:0] = (ieee_compliance == 3) ?
                                         (a_NaN ? {1'b1, a[sig_width-2:0]} :
                                          b_NaN ? {1'b1, b[sig_width-2:0]} :
                                          CW_NaN[sig_width-1:0]) :
                                          CW_NaN[sig_width-1:0];
          3'b01z: z_out[sig_width-1:0] = M_Zero;
          3'b001: z_out[sig_width-1:0] = M_MaxNorm;
          3'b000: z_out[sig_width-1:0] = F_sig_round[sig_width-1:0];
        endcase
      end

    end
    
    assign z = z_out;

    assign status[0] = ZERO     ;
    assign status[1] = INFINITY ;
    assign status[2] = INVALID  ;
    assign status[3] = TINY     ;
    assign status[4] = HUGE     ;
    assign status[5] = INEXACT  ;
    assign status[6] = 0        ; //HugeInt Reserved to 0
    assign status[7] = DIVZERO  ; //PassA/DivideByZero Reserved to 0

  end // ieee_compliance = 1
  else begin : arch1_ieee_0

    wire                         sign_check               ;
    wire                         Sticky                   ;
    wire [exp_width-1:0]         bias                     ;
    wire [2*sig_width +1:0]      sig_initial,sh_op        ;
    wire [sig_width+4:0]         sig_nor                  ;
    wire                         Inf_Result               ;
    wire [exp_width+1:0]         EXP_in_out               ;
    wire [exp_width:0]           overexp                  ;
    wire [$clog2(sig_width+4):0] shiftamount              ;
    wire [exp_width-1:0]         a_exp                    ;
    wire [exp_width-1:0]         b_exp                    ;
    wire [sig_width-1:0]         a_sig                    ;
    wire [sig_width-1:0]         b_sig                    ;
    wire [exp_width-1:0]         EXP_big_out_f            ;
    wire [exp_width+sig_width:0] INVALID_o                ;
    wire [exp_width+sig_width:0] p_MN                     ;
    wire [exp_width+sig_width:0] neg_MN                   ;
    wire [exp_width+sig_width:0] p_MxN                    ;
    wire [exp_width+sig_width:0] n_MxN                    ;
    wire [exp_width+sig_width:0] p_I                      ;
    wire [exp_width+sig_width:0] n_I                      ;
    wire [exp_width+sig_width:0] p_Z                      ;
    wire [exp_width+sig_width:0] n_Z                      ;
    wire                         EXP_check_over           ;
    wire                         EX                       ;
    wire                         a_sign                   ;
    wire                         b_sign                   ;
    wire  [sig_width-1:0]        sig_normalize_final_over ;
    wire                         a_Einf                   ;
    wire                         b_Einf                   ;
    wire                         a_sig0                   ;
    wire                         b_sig0                   ;
    wire                         a_NaN                    ;
    wire                         b_NaN                    ;
    wire                         a_denorm                 ;
    wire                         b_denorm                 ;
    wire                         a_Inf                    ;
    wire                         b_Inf                    ;
    wire                         a_zero                   ;
    wire                         b_zero                   ;

    wire [exp_width-1:0]         a_exp_n ;
    wire [exp_width-1:0]         b_exp_n ;

    wire                         merge;
    wire [2*(sig_width+5)-1:0]   sample ;
    wire [sig_width+3:0]         sig_nor_col;

    wire                         ov_fl ;
    wire                         both_zero ;

    reg                          x                   ;
    reg [$clog2(sig_width+4):0]  left_shift_count_1  ;
    reg                          oflow               ;
    reg                          uflow               ;
    reg [exp_width-1:0]          EXP_in_out_1        ;
    reg [sig_width+3:0]          sig_normalize       ;
    reg [sig_width+1:0]          sig_normalize_final ;
    reg [exp_width-1:0]          EXP_big_out_fin     ;
    reg [sig_width+exp_width:0]  z_f                 ;
    reg                          INVALID             ;
    reg                          INFINITY            ;
    reg                          INEXACT             ;
    reg                          ZERO                ;
    reg                          TINY                ;
    reg                          HUGE                ;
    reg                          FL1                 ;
    reg                          FL2                 ;

    assign a_exp  = a[sig_width+exp_width-1:sig_width]                  ;
    assign b_exp  = b[sig_width+exp_width-1:sig_width]                  ;
    assign a_sig  = a[sig_width-1:0]                                    ;
    assign b_sig  = b[sig_width-1:0]                                    ;
    assign a_sign = a[sig_width+exp_width]                              ;
    assign b_sign = b[sig_width+exp_width]                              ;
    assign bias   = (2 ** (exp_width-1)) -1                             ;
    assign p_MN   = {1'b0,{(exp_width-1){1'b0}},1'b1,{sig_width{1'b0}}} ;
    assign neg_MN = {1'b1,{(exp_width-1){1'b0}},1'b1,{sig_width{1'b0}}} ;
    assign p_MxN  = {1'b0,{(exp_width-1){1'b1}},1'b0,{sig_width{1'b1}}} ;
    assign n_MxN  = {1'b1,{(exp_width-1){1'b1}},1'b0,{sig_width{1'b1}}} ;
    assign p_I    = {1'b0,{(exp_width){1'b1}},       {sig_width{1'b0}}} ;
    assign n_I    = {1'b1,{(exp_width){1'b1}},       {sig_width{1'b0}}} ;
    assign p_Z    = {1'b0,{(exp_width+sig_width){1'b0}}}                ;
    assign n_Z    = {1'b1,{(exp_width+sig_width){1'b0}}}                ;
    
    /*----------------------------------------------------
    * Special FP numbers:
    * Note: These special Numbers are used when ieee_compliance=1
    * ========================================================
    * FP Number    ||| FP representation (Sign,Exp,Fraction)
    * ========================================================
    * //    +/- Zero       ||| (0 or 1,0,0)
    * //    +/- Infinity   ||| (0 or 1,Einf,0)
    * //    NaN        ||| (0,Einf,1) when generated by component.
    * //               (0 or 1, Einf, != 0 ) as input.
    * //    Denormal       ||| (0 or 1,0,any bit vector)
    ----------------------------------------------------*/

    assign a_Einf   = (a_exp=={exp_width{1'b1}});
    assign b_Einf   = (b_exp=={exp_width{1'b1}});
    assign a_sig0   = (a_sig=={sig_width{1'b0}});
    assign b_sig0   = (b_sig=={sig_width{1'b0}});

    ///////////////////////////////////////
    ////    NaN=> Exp= all 1's , Sig != 0;
    ///////////////////////////////////////

    assign a_NaN    = (a_Einf & ~a_sig0);
    assign b_NaN    = (b_Einf & ~b_sig0);

    ////////////////////////////////////////////
    ////    Denormals=> Exp= all 0's
    ////////////////////////////////////////////

    assign a_denorm = (a_exp=={exp_width{1'b0}}) && ~a_sig0;
    assign b_denorm = (b_exp=={exp_width{1'b0}}) && ~b_sig0;

    //////////////////////////////////////////
    ////    Infinity=> Exp= all 1's , Sig = 0;
    //////////////////////////////////////////

    assign a_Inf    = (ieee_compliance==0) ? a_Einf : a_Einf && (a_sig=={sig_width{1'b0}});
    assign b_Inf    = (ieee_compliance==0) ? b_Einf : b_Einf && (b_sig=={sig_width{1'b0}});

    ////////////////////////////////////////////
    ////   Zero=> Exp= all 0's and Sig = 0;
    ////////////////////////////////////////////
    assign a_zero =  (ieee_compliance==0) ? (~|a_exp)  : (a_exp=={exp_width{1'b0}})  && (a_sig=={sig_width{1'b0}});
    assign b_zero =  (ieee_compliance==0) ? (~|b_exp)  : (b_exp=={exp_width{1'b0}})  && (b_sig=={sig_width{1'b0}});

    //////////////////////////////////
    //Multiplication
    //////////////////////////////////

    assign a_exp_n   =  (a_denorm ? 1 : a_exp);
    assign b_exp_n   =  (b_denorm ? 1 : b_exp);
    assign SPECIAL   =  (ieee_compliance==0) ? (a_Inf | b_Inf) : (a_Inf | b_Inf) | (a_NaN | b_NaN);
    
    assign sign_check     = a_sign ^ b_sign;
    assign EXP_in_out     = (ieee_compliance==0)  & ((a_exp=={exp_width{1'b0}})  | (b_exp=={exp_width{1'b0}})) ? 0 : (a_exp_n + b_exp_n) - bias;
    assign EXP_check_over = ((EXP_in_out[exp_width+1]==0) & (EXP_in_out >  ((2**exp_width)-2))) ? 1 : 0;
    assign sig_initial    =  (ieee_compliance==0) ? {(1'b1),a_sig}  * {(1'b1),b_sig} : {~a_denorm,a_sig}  *  {~b_denorm,b_sig};

    // Note: we have the seeming vacuous +(sig_width<=2) below in order to prevent an error in simulation in the case when sig_width = 2
    assign sig_nor = (sig_width > 2) ? {sig_initial[2*sig_width+1:sig_width-2],(|sig_initial[sig_width+(sig_width<=2)-3:0])} :
                                       {sig_initial[2*sig_width+1:sig_width-2],1'b0};

    always @(*) begin
      left_shift_count_1= $lead0(sig_nor[sig_width+3:0]);
    end


    assign overexp         =  (EXP_in_out[exp_width-1:0] - left_shift_count_1);
    assign shiftamount       = (overexp[exp_width]==1  || ~|overexp )  ? (EXP_in_out!=0 ? EXP_in_out-1 : EXP_in_out) : left_shift_count_1;
    assign  EXP_big_out_f    = (overexp[exp_width]==1 || ~|overexp ) ? 0 : EXP_in_out[exp_width-1:0] - shiftamount;
    or   i_rs(merge,sig_nor[1],sig_nor[0]);
    ///////////////////////
    function automatic [sig_width+exp_width:0] min;
      input [sig_width+exp_width:0] a_w,b_w;
      begin
        if (a_w > b_w)
          min = b_w;
        else if (a_w == b_w)
          min = a_w;
        else
          min = a_w;
      end
    endfunction

    assign  sample = {sig_nor[sig_width+4:0],{(sig_width+4){1'b0}}} >> min ((bias - (a_exp_n + b_exp_n)+1 ),((sig_width+5)-(sig_nor[sig_width+4]? 0:left_shift_count_1)));
    assign sig_nor_col[0] = |sample[(sig_width+5)-1:0];
    assign sig_nor_col[sig_width+3:1] = sample[2*(sig_width+5)-1:(sig_width+5)];
    assign sh_op = sig_initial << shiftamount;

    ///////////////////////

    always @(*) begin
      if (ieee_compliance > 0) begin
        if (EXP_in_out[exp_width+1] ==1 || ~|EXP_in_out) begin
          //     sig_normalize =   {sig_nor_col[sig_width+3:1],(sig_nor_col[0]|sig_nor[0])};
          sig_normalize =   sig_nor_col[sig_width+3:0];
          EXP_in_out_1      = (sig_normalize[sig_width+3] ==1) ? 1 : 0;
        end
        else begin
          if (((sig_nor[sig_width+2+2:sig_width+2+1]==2'b10) | (sig_nor[sig_width+2+2:sig_width+2+1]==2'b11))) begin
            sig_normalize     = {sig_nor[sig_width+4:2],merge} ;
            EXP_in_out_1      = EXP_in_out[exp_width-1:0] +1;
          end
          else if ((sig_nor[sig_width+2+2:sig_width+2+1]==2'b01)) begin
            sig_normalize     = sig_nor[sig_width+3:0];
            EXP_in_out_1      = EXP_in_out[exp_width-1:0];
          end
          else begin
            // Note: we have the seeming vacuous +(sig_width<=2) below in order to prevent an error in simulation in the case when sig_width = 2
            sig_normalize     =  (sig_width > 2) ? {sh_op[2*sig_width-1:sig_width-2], (|sh_op[sig_width+(sig_width<=2)-3:0])} :
                                                   {sh_op[2*sig_width-1:sig_width-2], 1'b0}; //sig_nor[sig_width+3:0] << shiftamount;
            EXP_in_out_1      =  EXP_big_out_f;
          end
        end
      end
      else begin  // ieee_compliance==0
        if (~|EXP_in_out) begin
          sig_normalize     = {sig_nor[sig_width+4:2],merge} ;
          x = sig_nor[sig_width+4] ? 1 : 0;
        end
        else if (EXP_in_out[exp_width+1] ==1) begin
          if (&EXP_in_out) begin
            sig_normalize     = {sig_nor[sig_width+4:3],(sig_nor[2] | merge)};
            x = sig_nor[sig_width+4] ? 1 : 0;
          end
          else begin
            sig_normalize     =  0;
            x = 0;
          end
        end
        else if ((sig_nor[sig_width+2+2]==1'b1)) begin
          sig_normalize     = {sig_nor[sig_width+4:2],merge} ;
          x = 1;
        end
        else begin
          sig_normalize     = sig_nor[sig_width+3:0] ;
          x = 0;
        end
      end
    end

    always @(*) begin
      if (ieee_compliance > 0) begin
        oflow= (EXP_in_out_1=={{(exp_width-1){1'b1}},1'b1})  ;
        case(rnd)
          3'b000 :  begin
            if ((sig_normalize[3:2] ==2'b11) || (sig_normalize[2:1]==2'b11) || (sig_normalize[2] & sig_normalize[0])) begin
              sig_normalize_final ={1'b0,sig_normalize[sig_width+3:3]} +1 ;
              if (&sig_normalize[sig_width+2:3]) begin
                EXP_big_out_fin = 1 + EXP_in_out_1 ;
                oflow = (EXP_in_out_1=={{(exp_width-1){1'b1}},1'b0}) ;
              end
              else begin
                EXP_big_out_fin = EXP_in_out_1;
              end
            end
            else begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
              EXP_big_out_fin = EXP_in_out_1;
            end
          end
          3'b001:   begin
            sig_normalize_final =  {1'b0,sig_normalize[sig_width+3:3]};
            EXP_big_out_fin =  EXP_in_out_1;
          end
          3'b010:  begin
            if ((sign_check==0) & (sig_normalize[2] | sig_normalize[1] | sig_normalize[0])) begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} + 1;
              if (&sig_normalize[sig_width+2:3]) begin
                EXP_big_out_fin = 1 + EXP_in_out_1;
                oflow = (EXP_in_out_1=={{(exp_width-1){1'b1}},1'b0});
              end
              else begin
                EXP_big_out_fin = EXP_in_out_1;
              end
            end
            else begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
              EXP_big_out_fin =  EXP_in_out_1;
            end
          end
          3'b011:  begin
            if (sign_check & (sig_normalize[2] | sig_normalize[1] | sig_normalize[0]))  begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} +1;
              if (&sig_normalize[sig_width+2:3]) begin
                EXP_big_out_fin = 1 + EXP_in_out_1;
                oflow = (EXP_in_out_1=={{(exp_width-1){1'b1}},1'b0}) ;
              end
              else begin
                EXP_big_out_fin = EXP_in_out_1;
              end
            end
            else begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
              EXP_big_out_fin =  EXP_in_out_1;
            end
          end
                    3'b100:  begin
            if (sig_normalize[2] && ((~sign_check) || (|sig_normalize[1:0]))) begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} +1;
              if (&sig_normalize[sig_width+2:3]) begin
                EXP_big_out_fin = 1 + EXP_in_out_1;
                oflow = (EXP_in_out_1=={{(exp_width-1){1'b1}},1'b0}) ;
              end
              else begin
                EXP_big_out_fin = EXP_in_out_1;
              end
            end
            else begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
              EXP_big_out_fin =  EXP_in_out_1;
            end
          end
          3'b101:  begin
            if ((sig_normalize[2] | sig_normalize[1] | sig_normalize[0])) begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} +1;
              if (&sig_normalize[sig_width+2:3]) begin
                EXP_big_out_fin = 1 + EXP_in_out_1;
                oflow = (EXP_in_out_1=={{(exp_width-1){1'b1}},1'b0});
              end
              else begin
                EXP_big_out_fin = EXP_in_out_1;
              end
            end
            else begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
              EXP_big_out_fin =  EXP_in_out_1;
            end
          end
          default : begin
            sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
            EXP_big_out_fin =  EXP_in_out_1;
          end
        endcase
        //uflow = (sig_normalize_final[sig_width]==1'b0);
      end
      else begin
        FL1    = 0;
        if (EXP_in_out=={{(exp_width-1){1'b1}},1'b0})
          FL2 = 1;
        else
          FL2 = 0;
        uflow  = 0;
        oflow  = (FL2*(x));
        case(rnd)
          3'b000 :  begin
            if ((sig_normalize[3:2] ==2'b11) || (sig_normalize[2:1]==2'b11) || (sig_normalize[2] & sig_normalize[0])) begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} + 1;
              if (&sig_normalize[sig_width+2:3]) begin
                FL1 = 1;
                if (((EXP_in_out==(({exp_width{1'b1}})-2))*sig_nor[sig_width+2+2])| (FL2))
                  oflow = 1;
                else
                  oflow = 0;
              end
            else begin
                uflow = ~sig_normalize[sig_width+3];
              end
            end
            else begin
              uflow = ~sig_normalize[sig_width+3];
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
            end
          end
          3'b001:   begin
            uflow = ~sig_normalize[sig_width+3];
            sig_normalize_final =  {1'b0,sig_normalize[sig_width+3:3]};
          end
          3'b010:  begin
            if ((sign_check==0) & (sig_normalize[2] | sig_normalize[1] | sig_normalize[0])) begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} + 1;
              if (&sig_normalize[sig_width+2:3]) begin
                FL1 = 1;
                if (((EXP_in_out==(({exp_width{1'b1}})-2))*sig_nor[sig_width+2+2])| (FL2))
                  oflow = 1;
                else
                  oflow = 0;
              end
              else begin
                uflow = ~sig_normalize[sig_width+3];
              end
            end
            else begin
              uflow = ~sig_normalize[sig_width+3];
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
            end
          end
          3'b011:  begin
            if (sign_check & (sig_normalize[2] | sig_normalize[1] | sig_normalize[0]))  begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} +1;
              if (&sig_normalize[sig_width+2:3]) begin
                FL1 = 1;
                if (((EXP_in_out==(({exp_width{1'b1}})-2))*sig_nor[sig_width+2+2])| (FL2))
                  oflow = 1;
                else
                  oflow = 0;
              end
              else begin
                uflow = ~sig_normalize[sig_width+3];
              end
            end
            else begin
              uflow = ~sig_normalize[sig_width+3];
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
            end
          end
          3'b100:  begin
            if (sig_normalize[2] && ((~sign_check) || (|sig_normalize[1:0]))) begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} +1;
              if (&sig_normalize[sig_width+2:3]) begin
                FL1 = 1;
                if (((EXP_in_out==(({exp_width{1'b1}})-2))*sig_nor[sig_width+2+2])| (FL2))
                  oflow = 1;
                else
                  oflow = 0;
              end
              else begin
                uflow = ~sig_normalize[sig_width+3];
              end
            end
            else begin
              uflow = ~sig_normalize[sig_width+3];
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
            end
          end
          3'b101:  begin
            if ((sig_normalize[2] | sig_normalize[1] | sig_normalize[0])) begin
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]} +1;
              if (&sig_normalize[sig_width+2:3]) begin
                FL1    = 1;
                if (((EXP_in_out==(({exp_width{1'b1}})-2))*sig_nor[sig_width+2+2])| (FL2))
                  oflow = 1;
                else
                  oflow = 0;
              end
              else begin
                uflow = ~sig_normalize[sig_width+3];
              end
            end
            else begin
              uflow = ~sig_normalize[sig_width+3];
              sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
            end
          end
          default : begin
            uflow = ~sig_normalize[sig_width+3];
            sig_normalize_final = {1'b0,sig_normalize[sig_width+3:3]};
          end
        endcase
        EXP_big_out_fin =  EXP_in_out+FL1+x;
      end
    end
    assign  sig_normalize_final_over = sig_normalize_final[sig_width-1:0];

    assign INVALID_o  = {return_signed_nans ? sign_check : 1'b0, {exp_width{1'b1}}, {sig_width-1{1'b0}}, 1'b1};
    assign Inf_Result   = ~INVALID & ((a_Inf | b_Inf));
    assign ov_fl = (oflow| EXP_check_over);
    assign both_zero = (a_zero | b_zero);
    always @(*) begin
      if (ieee_compliance > 0) begin
        INVALID  = (((a_Inf & b_zero) | (b_Inf & a_zero)) | (a_NaN | b_NaN));
        INFINITY = ~INVALID & ((a_Inf | b_Inf) | ((ov_fl) & ((~sign_check & ((rnd==0) | (rnd==2) | (rnd==4) | (rnd==5))) | (sign_check & ((rnd==0) | (rnd==3) | (rnd==4) | (rnd==5))))));
        INEXACT  =  ~SPECIAL &  ~(both_zero) & (|sig_normalize[2:0] | (ov_fl)  );
        ZERO     =  ~SPECIAL & (EXP_check_over == 0) & ((~|sig_normalize_final_over & ~|EXP_big_out_fin) | (both_zero) ) ;
        TINY     =   ~(both_zero) & ~ov_fl & ((~|EXP_in_out_1) & INEXACT);
        HUGE     =   (~SPECIAL & ov_fl);
      end
      else begin
        INVALID  =  ((a_Inf & b_zero) | (b_Inf & a_zero))  ;
        INFINITY =  SPECIAL | ((ov_fl)&((~sign_check & ((rnd==0) | (rnd==2) |(rnd==4) | (rnd==5))) | (sign_check & ((rnd==0) | (rnd==3) |(rnd==4) | (rnd==5)))));
        INEXACT  =  ~SPECIAL & (sig_nor[2] | sig_nor[1] | sig_nor[0] | ov_fl | uflow |  (|sig_normalize[2:0])) && ~(both_zero);
        ZERO     =  ~SPECIAL & (((both_zero)) |  (uflow & ((~sign_check & ((rnd==3'b000) | (rnd==3'b001) | (rnd==3'b011) | (rnd==3'b100) | (rnd==3'b110) | (rnd==3'b111))) |(sign_check & ((rnd==3'b000) | (rnd==3'b001) | (rnd==3'b010) | (rnd==3'b100) | (rnd==3'b110) | (rnd==3'b111))) )));
        TINY     =  ~(both_zero) & (EXP_in_out[exp_width+1] | ~x & ~|EXP_in_out[exp_width:0]);
        HUGE     =   (~SPECIAL & ov_fl) ;
      end
    end


    always @(*) begin

      if (ieee_compliance > 0) begin
        if(INVALID)
          z_f = INVALID_o;
        else if (Inf_Result)
          z_f = {sign_check,{(exp_width){1'b1}},       {sig_width{1'b0}}};
        else if (both_zero)
          z_f = {sign_check,{(exp_width+sig_width){1'b0}}};
        else if (~SPECIAL & ov_fl) begin
          if (~sign_check) begin
            if ((rnd==0) | (rnd==2) | (rnd==4) | (rnd==5))
              z_f = p_I;
            else                // (rnd==3'b110) | (rnd==3'b111)
              z_f = p_MxN;
          end
          else begin
            if ((rnd==0) | (rnd==3) | (rnd==4) | (rnd==5))
              z_f = n_I;
            else                // (rnd==3'b110) | (rnd==3'b111)
              z_f = n_MxN;
          end
        end
        else
          z_f = {sign_check,EXP_big_out_fin,sig_normalize_final_over[sig_width-1:0]};
      end
      else begin
        if (INVALID)  begin
          z_f = {return_signed_nans ? sign_check : 1'b0, {(exp_width){1'b1}}, {sig_width{1'b0}}};
        end
        else if (SPECIAL) begin
          z_f = {sign_check,{(exp_width){1'b1}},{sig_width{1'b0}}};
        end
        else if (both_zero) begin
          z_f = {sign_check,{(exp_width+sig_width){1'b0}}};
        end
        else if (uflow) begin
          if (~sign_check) begin
            if ((rnd==3'b000) | (rnd==3'b001) | (rnd==3'b011) | (rnd==3'b100) | (rnd==3'b110) | (rnd==3'b111)) begin
              z_f = p_Z;
            end
            else
              z_f = p_MN;
          end
          else begin
            if ((rnd==3'b000) | (rnd==3'b001) | (rnd==3'b010) | (rnd==3'b100) | (rnd==3'b110) | (rnd==3'b111)) begin
              z_f = n_Z;
            end
            else
              z_f = neg_MN;
          end
        end
        else if (~SPECIAL& ov_fl) begin
          if (~sign_check) begin
            if ((rnd==0) | (rnd==2) | (rnd==4) | (rnd==5)) begin
              z_f = p_I;
            end
            else
              z_f = p_MxN;
          end
          else begin
            if ((rnd==0) | (rnd==3) | (rnd==4) | (rnd==5)) begin
              z_f = n_I;
            end
            else
              z_f = n_MxN;
          end
        end

        else  begin
          z_f = {sign_check,EXP_big_out_fin,sig_normalize_final_over[sig_width-1:0]};
        end
      end
    end

    assign z = z_f;

     assign status[0]   = ZERO     ;
    assign status[1]   = INFINITY ;
    assign status[2]   = INVALID  ;
    assign status[3]   = TINY     ;
    assign status[5]   = INEXACT  ;
    assign status[7:6] = 0        ;
    assign status[4]   = HUGE     ;

  end // ieee_compliance = 0

endmodule


/******************************************************************************
*  CW_fp_mult__non_compliant                                                 *
*****************************************************************************/

module CW_fp_mult__non_compliant(a, b, rnd, z, status);

  //----------------------------------------
  // Parameter
  //----------------------------------------

  parameter  sig_width          = 23; // Half => 10, Single => 23, Double => 52
  parameter  exp_width          = 8;  // Half => 5,  Single => 8,  Double => 11
  parameter  return_signed_nans = 0;

  //----------------------------------------
  // Input
  //----------------------------------------
  input      [exp_width+sig_width:0] a;
  input      [exp_width+sig_width:0] b;
  input      [2:0]                   rnd;

  //----------------------------------------
  // Output
  //----------------------------------------
  output reg [exp_width+sig_width:0] z;
  output reg [7:0]                   status;

  reg [sig_width-1:0]   a_sig, b_sig, res_sig;
  reg [exp_width-1:0]   a_exp, b_exp, res_exp;
  reg                   a_sgn, b_sgn, res_sgn;
  reg                   a_zero, b_zero, res_zero;
  reg                   a_inf, b_inf, res_inf;
  reg                   res_nan;

  reg [2*sig_width+1:0] sig_prod, sig_prod_ru_1, sig_prod_ru_2;
  reg [exp_width+1:0]   exp_sum, exp_sum_add_1;
  reg                   pre_shift, post_shift;

  reg [1:0]             sticky_extra;
  reg                   res_odd, res_even, round_bit, sticky_bit, inc_res;
  reg                   underflow, stays_udf, udf_up, overflow, ovf_up;
  reg                   INEXACT, HUGE, TINY, INVALID, INFINITY, ZERO;

  always @ (*) begin
    /** Input signals and exceptions */
    a_sig          = a[sig_width-1:0];
    b_sig          = b[sig_width-1:0];
    a_exp          = a[exp_width+sig_width-1:sig_width];
    b_exp          = b[exp_width+sig_width-1:sig_width];
    a_sgn          = a[exp_width+sig_width];
    b_sgn          = b[exp_width+sig_width];

    a_zero         = ~(|a_exp);
    b_zero         = ~(|b_exp);
    a_inf          = &a_exp;
    b_inf          = &b_exp;

    /** Calculation */
    sig_prod       = {1'b1, a_sig} * {1'b1, b_sig};
    sig_prod_ru_1  = sig_prod + {{sig_width+1{1'b0}}, 1'b1, {sig_width{1'b0}}};
    sig_prod_ru_2  = sig_prod + {{sig_width{1'b0}}, 1'b1, {sig_width+1{1'b0}}};

    exp_sum        = a_exp + b_exp - {1'b0, {exp_width-1{1'b1}}};
    exp_sum_add_1  = a_exp + b_exp - {1'b0, {exp_width-1{1'b1}}} + 1'b1;

    // Before rounding
    pre_shift      = sig_prod[2*sig_width+1];
    underflow      = (~pre_shift & ($signed(exp_sum) <= $signed(1'b0))) ||
                     (pre_shift & ($signed(exp_sum_add_1) <= $signed(1'b0)));

    case ({pre_shift, underflow})
      2'b00:  {res_odd, round_bit, sticky_extra} =
        {sig_prod[sig_width:sig_width-1], 2'b00};
      2'b01:  {res_odd, round_bit, sticky_extra} =
        {sig_prod[sig_width+1:sig_width-1], 1'b0};
      2'b10:  {res_odd, round_bit, sticky_extra} =
        {sig_prod[sig_width+1:sig_width-1], 1'b0};
      2'b11:  {res_odd, round_bit, sticky_extra} =
        sig_prod[sig_width+2:sig_width-1];
    endcase

    res_even   = ~res_odd;
    sticky_bit = (|sticky_extra) | (|sig_prod[sig_width-2:0]);
    res_sgn    = a_sgn ^ b_sgn;
    inc_res    = res_requires_increment(rnd, res_sgn, res_even, round_bit, sticky_bit);

    // Does rounding cause us to shift?
   post_shift     = pre_shift | inc_res & sig_prod_ru_1[2*sig_width+1];

    case ({post_shift, inc_res})
      2'b00:  res_sig = sig_prod[2*sig_width-1:sig_width];
      2'b01:  res_sig = sig_prod_ru_1[2*sig_width-1:sig_width];
      2'b10:  res_sig = sig_prod[2*sig_width:sig_width+1];
      2'b11:  res_sig = sig_prod_ru_2[2*sig_width:sig_width+1];
    endcase

    case (post_shift)
      1'b0:   res_exp = exp_sum[exp_width-1:0];
      1'b1:   res_exp = exp_sum_add_1[exp_width-1:0];
    endcase

    /** Exceptions */
    stays_udf      = (~post_shift & ($signed(exp_sum) <= $signed(1'b0))) ||
                     (post_shift & ($signed(exp_sum_add_1) <= $signed(1'b0)));
    overflow       = $signed(exp_sum + post_shift) >
                     $signed({1'b0, {exp_width-1{1'b1}}, 1'b0});
    udf_up         = res_requires_increment(rnd, res_sgn, 1'b1, 1'b0, 1'b1);
    ovf_up         = res_requires_increment(rnd, res_sgn, 1'b1, 1'b1, 1'b1);
    res_zero       = (~a_inf & b_zero) | (a_zero & ~b_inf);
    res_inf        = (a_inf & ~b_zero) | (~a_zero & b_inf);
    res_nan        = (a_inf & b_zero) | (a_zero & b_inf);

    /** Status bits */
    ZERO           = res_zero | (stays_udf & ~udf_up);
    // z == +-0
    INFINITY       = res_inf | res_nan | (overflow & ovf_up);
    // z == +-Inf
    INVALID        = res_nan;
    // F == NaN
    HUGE           = ~(res_inf | res_nan) & overflow;
    // exact result not +- inf, but |rounded result| > max_norm
    INEXACT        = ~(res_zero | res_inf | res_nan) &
                     (round_bit | sticky_bit | overflow | underflow);
    // exact result is not equal to z
    TINY           = ~res_zero & underflow;
    // result is inexact and |exact result| < min_norm

    /** Output */
    casez ({res_zero | (stays_udf & ~udf_up),
      underflow & udf_up,
      res_inf | res_nan | (overflow & ovf_up),
      overflow & ~ovf_up})
      4'b1zzz:  z  = {res_sgn, {exp_width+sig_width{1'b0}}};
      4'b01zz:  z  = {res_sgn, {exp_width-1{1'b0}}, 1'b1, {sig_width{1'b0}}};
      4'b001z:  z  = {return_signed_nans ? res_sgn : res_sgn & ~res_nan,
        {exp_width{1'b1}}, {sig_width{1'b0}}};
      4'b0001:  z  = {return_signed_nans ? res_sgn : res_sgn & ~res_nan,
        {{exp_width-1{1'b1}},1'b0}, {sig_width{1'b1}}};
      4'b0000:  z  = {res_sgn, res_exp, res_sig};
    endcase

      status         = {1'b0, 1'b0, INEXACT, HUGE, TINY, INVALID, INFINITY, ZERO};

  end // always @ (*)

  /** Helper function */
  function automatic res_requires_increment(
    input [2:0] rnd,
    input       res_sgn,
    input       res_even,
    input       round_bit,
    input       sticky_bit);

    begin
      case(rnd)
        3'b000:  begin  // Round to nearest, even
          res_requires_increment = round_bit & (sticky_bit | ~res_even);
        end
        3'b001:  begin  // Round to zero
          res_requires_increment = 1'b0;
        end
        3'b010:  begin  // Round to + infinity
          res_requires_increment = ~res_sgn  & (round_bit | sticky_bit);
        end
        3'b011:  begin  // Round to - infinity
          res_requires_increment = res_sgn   & (round_bit | sticky_bit);
        end
        3'b100:  begin  // Round to nearest, up
          res_requires_increment = round_bit & (~res_sgn | sticky_bit);
        end
        3'b101:  begin  // Round away from zero
          res_requires_increment = round_bit | sticky_bit;
        end
        default: begin  // Don't care space - round to zero
          res_requires_increment = 1'b0;
        end
      endcase
    end
  endfunction

endmodule

module  CW_fp_mult__compliant (a, b, rnd, z, status);

  //----------------------------------------
  // Parameter
  //----------------------------------------
 parameter sig_width         = 23 ; // Half => 10, Single => 23, Double => 52
  parameter exp_width         = 8  ; // Half => 5,  Single => 8,  Double => 11
  parameter ieee_compliance   = 1  ;
  parameter return_signed_nans = 0   ; // Request from TI

  //----------------------------------------
  // Input 
  //----------------------------------------
  /** Interface */
  input      [exp_width+sig_width:0] a, b;
  input      [2:0]            rnd;

  //----------------------------------------
  // Output 
  //----------------------------------------
  output     [exp_width+sig_width:0] z      ;
  output     [7:0]                   status ;

  //----------------------------------------
  // Localparam
  //----------------------------------------
  localparam tiny_fix           = 1   ; // Existing component has a bug
  localparam float_bits         = 1 + exp_width + sig_width;

  //! computed parameters \todo put these into a class so that we can share across components
  //@{
  localparam [exp_width-1:0]         E_Inf       = {exp_width{1'b1}};
  localparam [exp_width-1:0]         E_Zero      = {exp_width{1'b0}};
  localparam [exp_width-1:0]         E_MinNorm   = {{(exp_width-1){1'b0}},1'b1};
  localparam [exp_width-1:0]         E_MaxNorm   = {{(exp_width-1){1'b1}},1'b0};
  localparam [sig_width-1:0]         M_Zero      = {sig_width{1'b0}};
  localparam [sig_width-1:0]         M_MaxNorm   = ~M_Zero;
  localparam [sig_width+exp_width:0] CW_NaN      = (ieee_compliance == 3) ? {1'b0,E_Inf,1'b1,{(sig_width-1){1'b0}}} :
                                                                            {1'b0,E_Inf,{(sig_width-1){1'b0}},1'b1};
  localparam [sig_width+exp_width:0] pos_MinNorm = {1'b0,E_MinNorm, M_Zero};
  localparam [sig_width+exp_width:0] neg_MinNorm = {1'b1,E_MinNorm, M_Zero};
  localparam [sig_width+exp_width:0] pos_MaxNorm = {1'b0,E_MaxNorm,~M_Zero};
  localparam [sig_width+exp_width:0] neg_MaxNorm = {1'b1,E_MaxNorm,~M_Zero};
  localparam [sig_width+exp_width:0] pos_Inf     = {1'b0,E_Inf    , M_Zero};
  localparam [sig_width+exp_width:0] neg_Inf     = {1'b1,E_Inf    , M_Zero};
  localparam [sig_width+exp_width:0] pos_Zero    = {1'b0,E_Zero   , M_Zero};
  localparam [sig_width+exp_width:0] neg_Zero    = {1'b1,E_Zero   , M_Zero};
  localparam [exp_width-1:0]         bias        = {1'b0,{(exp_width-1){1'b1}}};
  //@}
  localparam                         lzc_width = $clog2(sig_width+1);

  localparam                         F_exp_width_upper = 1+$clog2(bias+2*sig_width-2);
  localparam                         F_exp_width_lower = exp_width+2;
  localparam                         F_exp_width       = (F_exp_width_upper > F_exp_width_lower) ? F_exp_width_upper : F_exp_width_lower;
  localparam                         max_right_shift   = sig_width + 3;

  // Size of the storage we need for the right shift for denormailisation.
  localparam                         right_shift_width = $clog2(max_right_shift+1);
  // This is the exponent that shifts the leading one into the bit past the guard bit.
  // Shifting further cannot change the rounding.
  localparam signed                  E_Min            = E_MinNorm - (max_right_shift - 1);
  localparam signed                  E_Min_dec        = E_Min - 1;
  localparam                         max_fpp_lzc      = 2 + 2 * sig_width;
  localparam                         fpp_lzc_width    = $clog2(max_fpp_lzc+1);
  localparam                         max_left_shift   = (bias < sig_width + 2) ? max_fpp_lzc : sig_width; //sig_width?  I think I can tighten this for better ppa
  localparam                         left_shift_width = $clog2(max_left_shift+1);
  localparam                         wi               =sig_width;
  localparam                         wr               =$clog2(wi+1);

  reg [sig_width+exp_width:0]  z_out;
  //! decoded inputs
  //@{
  wire                          a_sign     , b_sign;
  wire [exp_width-1:0]          a_exp      , b_exp;
  wire [sig_width-1:0]          a_sig      , b_sig;
  //@}

  //! functions of the a/b inputs
  //@{
  wire                              a_E_Inf    , b_E_Inf ;    //!< a/b has an "Inf" exponent
  wire                              a_E_Zero   , b_E_Zero ;   //!< a/b has a "Zero" exponent
  wire                              a_M_Zero   , b_M_Zero;    //!< a/b has a "Zero" mantissa
  wire                              a_NaN      , b_NaN;       //!< a/b is NaN
  wire                              a_sNaN     , b_sNaN;
  wire                              a_Denorm   , b_Denorm;    //!< a/b is Denorm
  wire                              a_Inf      , b_Inf;       //!< a/b is Inf
  wire                              a_Zero     , b_Zero;      //!< a/b is Zero
  //@}

  wire [sig_width:0]            a_sig_norm         ;
  wire [sig_width:0]            b_sig_norm         ;
  wire [lzc_width-1:0]          a_LZC              ;
  wire [lzc_width-1:0]          b_LZC              ;
  wire                          F_sign             ;
  wire                          F_NaN              ;
  wire                          Signal_NaN         ;
  wire                          F_Zero             ;
  wire                          F_Inf              ;
  wire                          F_Special          ;
  wire signed [F_exp_width-1:0] F_exp_pre_norm     ;
  wire signed [F_exp_width-1:0] F_exp_pre_norm_inc ;

  // bias >;
  // entirety of fpp into sticky bits so we can shift back by any amount that doesn't shift out
  // leading ones.  That means we don't need to add the two LZCs and we can reduce the shifter
  // width significantly.
  wire [(sig_width + 2)-1:0]    F_sig_round;  

  // Calculate conditions of shift right 
  wire                          shf_0 ;
  wire                          shf_1 ;
  // The right shift for denormalisation.
  wire [right_shift_width-1:0]  right_shift  ;

  wire [fpp_lzc_width-1:0]      fpp_lzc                   ;
  wire [left_shift_width-1:0]   left_shift                ;

  wire                         lr_shift         ;
  wire [left_shift_width-1:0]  left_right_shift ;
  wire [right_shift_width-1:0] right_left_shift ;

  wire [(sig_width*2 + 2)-1:0]  fpp_pre_shift          ;
  wire [(sig_width*2 + 2)-1:0]  fixed_point_product    ;
  wire signed [F_exp_width-1:0] F_exp                  ;
  wire [(sig_width*2 + 2)+3:0]  fixed_point_product_lr ;

  wire [(sig_width + 2)-1:0]    F_sig        ;
  wire [(sig_width + 4)-1:0]    F_sig_extra  ;
  wire                          F_huge       ;
  wire                          F_tiny       ;
  wire                          guard        ;
  wire                          sticky       ;
  wire                          rnd_cont     ;
  wire                          exp_cont     ;
  wire signed [F_exp_width-1:0] F_exp_round  ;
  wire                          F_huge_round ;
  wire                          F_tiny_round ;
  wire                          Z_Zero       ;
  wire                          Z_Inf        ;
  wire                          Z_sign       ;
  wire                          ZERO         ;
  wire                          INFINITY     ;
  wire                          INVALID      ;
  wire                          TINY         ;
  wire                          HUGE         ;
  wire                          INEXACT      ;
  wire                          DIVZERO      ;

  //! bring in the rounding tools
  function automatic round_up;
    input [2:0] rnd;
    input sign;
    input odd;
    input guard;
    input sticky;
        begin
      casez(rnd)
        3'b000 : round_up = guard & (sticky | odd);   //RTE
        3'b001 : round_up = 1'b0;                     //RTZ
        3'bz10 : round_up = ~sign & (guard | sticky); //RTPI
        3'bz11 : round_up = sign & (guard | sticky);  //RTNI
        3'b100 : round_up = guard & (sticky | ~sign); //RTU ? round to nearest, up
        3'b101 : round_up = guard | sticky;           //RAZ
      endcase
    end
  endfunction

  function automatic huge_is_inf;
    input [2:0] rnd;
    input sign;
    begin
      casez(rnd)
        3'b000 : huge_is_inf = 1'b1;  //RTE
        3'b001 : huge_is_inf = 1'b0;  //RTZ
        3'bz10 : huge_is_inf = ~sign; //RTPI
        3'bz11 : huge_is_inf = sign;  //RTNI
        3'b100 : huge_is_inf = 1'b1;  //RTU
        3'b101 : huge_is_inf = 1'b1;  //RAZ
      endcase
    end
  endfunction

  function automatic tiny_is_zero;
    input [2:0] rnd;
    input sign;
    begin
      casez(rnd)
        3'b000 : tiny_is_zero = 1'b1;  //RTE
        3'b001 : tiny_is_zero = 1'b1;  //RTZ
        3'bz10 : tiny_is_zero = sign;  //RTPI
        3'bz11 : tiny_is_zero = ~sign; //RTNI
        3'b100 : tiny_is_zero = 1'b1;  //RTU
        3'b101 : tiny_is_zero = 1'b0;  //RAZ
      endcase
    end
  endfunction

  //! Decode the a/b inputs
  //@{
  assign {a_sign , a_exp  , a_sig} = a;
  assign {b_sign , b_exp  , b_sig} = b;

  assign {a_E_Inf         , b_E_Inf     } = {a_exp==E_Inf           , b_exp==E_Inf           };
  assign {a_E_Zero        , b_E_Zero    } = {a_exp==E_Zero          , b_exp==E_Zero          };
  assign {a_M_Zero        , b_M_Zero    } = {a_sig==M_Zero          , b_sig==M_Zero          };
 assign {a_NaN           , b_NaN       } = (ieee_compliance==0)
                                            ? {1'b0                   , 1'b0                   }
                                            : {a_E_Inf  & ~a_M_Zero   , b_E_Inf  & ~b_M_Zero   };
  assign {a_sNaN          , b_sNaN      } = (ieee_compliance==3)
                                            ? {a_NaN & ~a[sig_width-1], b_NaN & ~b[sig_width-1]}
                                            : {a_NaN                  , b_NaN                  };
  assign {a_Denorm        , b_Denorm    } = (ieee_compliance==0)
                                            ? {1'b0                   , 1'b0                   }
                                            : {a_E_Zero & ~a_M_Zero   , b_E_Zero & ~b_M_Zero   };
  assign {a_Inf           , b_Inf       } = (ieee_compliance==0)
                                            ? {a_E_Inf                , b_E_Inf                }
                                            : {a_E_Inf  & a_M_Zero    , b_E_Inf  & b_M_Zero    };
  assign {a_Zero          , b_Zero      } = (ieee_compliance==0)
                                            ? {a_E_Zero               , b_E_Zero               }
                                            : {a_E_Zero & a_M_Zero    , b_E_Zero & b_M_Zero    };

  //@}


  //! Normalize the inputs
  //@{
  assign a_sig_norm = {~a_Denorm,a_sig};  // a significand after normalization
  assign b_sig_norm = {~b_Denorm,b_sig};  // b significand after normalization
  assign a_LZC      = a_Denorm ? $lead0(a_sig) : {lzc_width{1'b0}};
  assign b_LZC      = b_Denorm ? $lead0(b_sig) : {lzc_width{1'b0}};

  // F from the spec
  assign F_sign             = a_sign ^ b_sign;
  assign F_NaN              = a_NaN | b_NaN | (b_Inf & a_Zero) | (b_Zero & a_Inf);
  assign Signal_NaN         = a_sNaN | b_sNaN | b_Inf & a_Zero | b_Zero & a_Inf;
  assign F_Zero             = b_Zero & ~a_Inf & ~a_NaN | a_Zero & ~b_Inf & ~b_NaN;
  assign F_Inf              = b_Inf & ~a_Zero & ~a_NaN | a_Inf & ~b_Zero & ~b_NaN;
  assign F_Special          = F_Zero | F_Inf | F_NaN;

  assign F_exp_pre_norm     = a_exp + b_exp - bias - b_LZC - a_LZC;
  assign F_exp_pre_norm_inc = a_exp + b_exp - bias - b_LZC - a_LZC + {{exp_width-1{1'b0}},1'b1};

  // Calculate conditions of shift right 
  assign shf_0        = ((F_exp_pre_norm_inc <= $signed(E_MinNorm)) & (F_exp_pre_norm_inc <= E_Min));
  assign shf_1        = ((F_exp_pre_norm_inc <= $signed(E_MinNorm)) & !(F_exp_pre_norm_inc <= E_Min));
  // The right shift for denormalisation.
  assign right_shift  = shf_0 ? (max_right_shift - 1) : shf_1 ? $signed(E_MinNorm) - F_exp_pre_norm : {right_shift_width{1'b0}};

  assign fpp_lzc      = a_LZC + b_LZC + {{lzc_width-1{1'b0}},a_Denorm} + {{lzc_width-1{1'b0}},b_Denorm};

  assign left_shift   = ((ieee_compliance == 3) && (a_NaN || b_NaN)) ? 'b0 :
                        (bias < sig_width+2) ? (fpp_lzc > max_left_shift ? max_left_shift : fpp_lzc) : 
                                                      (a_Denorm ? {{lzc_width-1{1'b0}},1'b1} + a_LZC : b_Denorm ? {{lzc_width-1{1'b0}},1'b1} + b_LZC : {left_shift_width{1'b0}});

  assign lr_shift         = (left_shift >= right_shift);
  assign left_right_shift = left_shift-right_shift;
  assign right_left_shift = right_shift-left_shift;

  assign fpp_pre_shift = ((ieee_compliance == 3) && a_NaN) ? {1'b0, 1'b1, a_sig, {sig_width{1'b0}}} :
                         ((ieee_compliance == 3) && b_NaN) ? {1'b0, 1'b1, b_sig, {sig_width{1'b0}}} :
                         a_sig_norm * b_sig_norm;

  assign  fixed_point_product    = fpp_pre_shift << left_shift;
  assign  F_exp                  = fixed_point_product[(sig_width*2 + 2)-1] ? F_exp_pre_norm_inc : F_exp_pre_norm;
  assign  fixed_point_product_lr = (lr_shift ? {fpp_pre_shift, 4'b0} << (left_right_shift) : {fpp_pre_shift[(sig_width*2 + 2)-1:0], {4{1'b0}}} >> (right_left_shift)) >> (fixed_point_product[(sig_width*2 + 2)-1] & !shf_1 );

  assign F_sig       = {fixed_point_product_lr[(sig_width*2 + 2)+3:(sig_width*2 + 2)-(sig_width + 2)+4]};
  assign F_sig_extra = {fixed_point_product_lr[(sig_width*2 + 2)-(sig_width + 2)+3 : 0]};

  assign F_huge   = ~F_Special & (F_exp > $signed({1'b0, E_MaxNorm}));
  assign F_tiny   = ~F_Special & (F_exp < $signed({1'b0, E_MinNorm}));
  assign guard    = F_sig_extra[(sig_width + 4)-1];
  assign sticky   = |F_sig_extra[(sig_width + 4)-2:0] | (|fixed_point_product[(sig_width*2 + 2)-(sig_width + 2)-2:0]);
  assign rnd_cont = round_up(rnd, F_sign, F_sig[0], guard, sticky);

  assign exp_cont    = (~F_huge & F_sig_round[(sig_width + 2)-1] | F_tiny & F_sig_round[(sig_width + 2)-2]);
  assign F_exp_round = F_exp + {{F_exp_width-1{1'b0}},exp_cont};

  assign F_sig_round[(sig_width + 2)-3 : 0] = F_sig[(sig_width + 2)-3 : 0] + {{sig_width-1{1'b0}},rnd_cont};
  assign F_sig_round[(sig_width + 2)-1]     = rnd_cont ? (F_sig == {1'b0, {(sig_width + 2)-1{1'b1}}}) : F_sig[(sig_width + 2)-1];
  assign F_sig_round[(sig_width + 2)-2]     = rnd_cont ?  ~F_sig[(sig_width + 2)-2] & (& F_sig[(sig_width + 2)-3:0])   :   F_sig[(sig_width + 2)-2];
  assign F_huge_round                       = F_huge | ~F_Special & ((F_exp == (E_MaxNorm)) & exp_cont);
  assign F_tiny_round                       = F_tiny & ~F_Special & ~((F_exp == {F_exp_width{1'b0}}) & exp_cont);

  assign Z_Zero    = F_Zero | ~F_NaN & ~F_Inf & ~F_huge_round & ~F_NaN & ~F_Inf & ~F_huge_round &  (((F_sig == {(sig_width + 2){1'b1}}) & rnd_cont) | ((F_sig == {(sig_width + 2){1'b0}}) & !rnd_cont));
  assign Z_Inf     = F_Inf  | F_huge_round & huge_is_inf(rnd, F_sign);
  assign Z_sign    = return_signed_nans ? F_sign : F_sign & ~F_NaN;    
  assign ZERO      = Z_Zero;
  assign INFINITY  = Z_Inf;
  assign INVALID   = Signal_NaN;
  assign TINY      = ~F_Special & (tiny_fix ? F_tiny : F_tiny_round) & (!(ieee_compliance > 0) | sticky | guard);
  assign HUGE      = F_huge_round;
  assign INEXACT   = ~F_Special & (sticky | guard | F_huge_round | !(ieee_compliance > 0) & F_tiny_round);
  assign DIVZERO   = 1'b0;

   always @(*) begin
    // sign bit out
    z_out[sig_width+exp_width] = Z_sign;
    // exponent out
    casez({F_NaN, Z_Inf, F_huge_round, Z_Zero | F_tiny_round})
      4'b1zzz: z_out[sig_width+exp_width-1:sig_width] = CW_NaN[sig_width+exp_width-1:sig_width];
      4'b01zz: z_out[sig_width+exp_width-1:sig_width] = E_Inf;
      4'b001z: z_out[sig_width+exp_width-1:sig_width] = E_MaxNorm;
      4'b0001: z_out[sig_width+exp_width-1:sig_width] = E_Zero;
      4'b0000: z_out[sig_width+exp_width-1:sig_width] = F_exp_round[exp_width-1:0];
    endcase

    // significand out
    casez({F_NaN, Z_Inf | Z_Zero, F_huge_round})
      3'b1zz: z_out[sig_width-1:0] = (ieee_compliance == 3) ?
                                     // (a_NaN ? {1'b1, a[sig_width-2:0]} :
                                     //  b_NaN ? {1'b1, b[sig_width-2:0]} :
                                     ((a_NaN | b_NaN) ? {1'b1, F_sig_round[sig_width-2:0]} :
                                      CW_NaN[sig_width-1:0]) :
                                      CW_NaN[sig_width-1:0];
      3'b01z: z_out[sig_width-1:0] = M_Zero;
      3'b001: z_out[sig_width-1:0] = M_MaxNorm;
      3'b000: z_out[sig_width-1:0] = F_sig_round[sig_width-1:0];
    endcase

  end

  assign z = z_out;

  assign status[0] = ZERO     ;
  assign status[1] = INFINITY ;
  assign status[2] = INVALID  ;
  assign status[3] = TINY     ;
  assign status[4] = HUGE     ;
  assign status[5] = INEXACT  ;
  assign status[6] = 1'b0     ; //HugeInt Reserved to 0
  assign status[7] = DIVZERO  ; //PassA/DivideByZero Reserved to 0

endmodule // ieee_compliance = 1
                                 
            
