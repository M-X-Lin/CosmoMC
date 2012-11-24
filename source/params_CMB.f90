!Parameterization using theta = r_s/D_a instead of H_0, and tau instead of z_re
!and log(A_s) instead of A_s
!Less general, but should give better performance
!
!The well-determined parameter A_s exp(-2tau) should be found by the covariance matrix
!parameter 3 is 100*theta, parameter 4 is tau, others same as params_H except A->log(A)
!Theta is much better constrained than H_0
!
!AL Jul 2005 - fixed bug which screwed up tau values for later importance sampling
!AL Feb 2004 - fixed compiler compatibility issue with **-number, typo in zstar
!AL Dec 2003 - renamed from params_Kowosky, changed to tau - log(A)
!AL Sept 2003 - fixed bug in declaration of dtauda routine
!AL June 2003
!Assumes prior 0.4 < h < 1

   function CMBToTheta(CMB)
     use cmbtypes
     use ModelParams
     use CMB_Cls
     implicit none
     Type(CMBParams) CMB
     real(mcp) CMBToTheta
     integer error
  
     call InitCAMB(CMB,error,.false.)
     CMBToTheta = CosmomcTheta()

  end function CMBToTheta




!Mapping between array of power spectrum parameters and CAMB
     subroutine SetCAMBInitPower(P,CMB,in)
       use camb
       use settings
       use cmbtypes
       use CMB_Cls
       implicit none
       type(CAMBParams)  P
       Type(CMBParams) CMB

       integer, intent(in) :: in


       if (Power_Name == 'power_tilt') then

       P%InitPower%k_0_scalar = pivot_k
       P%InitPower%k_0_tensor = pivot_k

       P%InitPower%ScalarPowerAmp(in) = cl_norm*CMB%InitPower(As_index)
       P%InitPower%rat(in) = CMB%InitPower(amp_ratio_index)

        
       P%InitPower%an(in) = CMB%InitPower(1)
       P%InitPower%ant(in) = CMB%InitPower(2)
       if (P%InitPower%rat(in)>0 .and. .not. compute_tensors) &
        call MpiStop('computing r>0 but compute_tensors=F')
       P%InitPower%n_run(in) = CMB%InitPower(3)
       if (inflation_consistency) then
         P%InitPower%ant(in) = - CMB%InitPower(amp_ratio_index)/8.
          !note input n_T is ignored, so should be fixed (to anything)
       end if
       else
         stop 'params_CMB:Wrong initial power spectrum'
       end if

     end subroutine SetCAMBInitPower
 

 subroutine SetFast(Params,CMB)
     use settings
     use cmbtypes
     real(mcp) Params(num_Params)
     Type(CMBParams) CMB
     
        CMB%InitPower(1:num_initpower) = Params(index_initpower:index_initpower+num_initpower-1)
        CMB%InitPower(As_index) = exp(CMB%InitPower(As_index))
        CMB%data_params(1:num_freq_params) = Params(index_freq:index_freq+num_freq_params-1)
        CMB%nuisance(1:num_nuisance_params) = Params(index_nuisance:index_nuisance+num_nuisance_params-1)
 
 end subroutine SetFast

 subroutine SetForH(Params,CMB,H0, firsttime)
     use settings
     use cmbtypes
     use CMB_Cls
     use bbn
     implicit none
     real(mcp) Params(num_Params)
     logical, intent(in) :: firsttime
     Type(CMBParams) CMB
     real(mcp) h2,H0
     
  
    CMB%H0=H0
    if (firsttime) then
        CMB%reserved = 0
        CMB%ombh2 = Params(1)    
        CMB%tau = params(4) !tau, set zre later
        CMB%Omk = Params(5)
        if (neutrino_param_mnu) then
        !Params(6) is now mnu, params(2) is omch2
         CMB%omnuh2=Params(6)/93.04
         if (CMB%omnuh2 > 0 .and. (Params(9) < 3 .or. Params(9)>3.1)) &
            call MpiStop('params_CMB: change for non-standard nnu with massive nu')
         CMB%omch2 = Params(2)
         CMB%omdmh2 = CMB%omch2+ CMB%omnuh2
         CMB%nufrac=CMB%omnuh2/CMB%omdmh2
        else
         CMB%omdmh2 = Params(2)
         CMB%nufrac=Params(6)
         CMB%omnuh2 = CMB%omdmh2*CMB%nufrac
         CMB%omch2 = CMB%omdmh2 - CMB%omnuh2
        end if 
        CMB%w = Params(7)
        CMB%wa = Params(8)
        CMB%nnu = Params(9) !3.046
        
        if (bbn_consistency) then
         CMB%YHe = yp_bbn(CMB%ombh2,CMB%nnu  - 3.046)
        else
         !e.g. set from free parameter..
         CMB%YHe  =Params(10)
        end if
        
        CMB%iso_cdm_correlated =  Params(11)
        CMB%zre_delta = Params(12)
        CMB%ALens = Params(13)
        CMB%fdm = Params(14)
        call SetFast(Params,CMB)
    end if
    
    CMB%h = CMB%H0/100
    h2 = CMB%h**2
    CMB%omb = CMB%ombh2/h2
    CMB%omc = CMB%omch2/h2
    CMB%omnu = CMB%omnuh2/h2
    CMB%omdm = CMB%omdmh2/h2
    CMB%omv = 1- CMB%omk - CMB%omb - CMB%omdm

 end  subroutine SetForH

 subroutine ParamsToCMBParams(Params, CMB)
     use settings
     use cmbtypes
     use CMB_Cls

     implicit none
     real(mcp) Params(num_params)
     integer, parameter :: ncache =2
     real(mcp), save :: LastParams(num_params,ncache) = 0._mcp

     Type(CMBParams) CMB
     Type(CMBParams), save :: LastCMB(ncache)
     real(mcp) DA
     real(mcp)  D_b,D_t,D_try,try_b,try_t, CMBToTheta, lasttry
     external CMBToTheta
     integer, save :: cache=1
     integer i

     do i=1, ncache
      !want to save two slow positions for some fast-slow methods
       if (all(Params(1:num_hard) == Lastparams(1:num_hard, i))) then
        CMB = LastCMB(i)
        call SetFast(Params,CMB)
        return
       end if
     end do
     DA = Params(3)/100
     try_b = 40
     call SetForH(Params,CMB,try_b, .true.)
     D_b = CMBToTheta(CMB)
     try_t = 100
     call SetForH(Params,CMB,try_t, .false.)
     D_t = CMBToTheta(CMB)
     if (DA < D_b .or. DA > D_t) then
      cmb%H0=0 !Reject it
     else
     lasttry = -1
     do
            call SetForH(Params,CMB,(try_b+try_t)/2, .false.)
            D_try = CMBToTheta(CMB)
               if (D_try < DA) then
                  try_b = (try_b+try_t)/2
               else
                  try_t = (try_b+try_t)/2
               end if
               if (abs(D_try - lasttry)< 1e-7) exit
              lasttry = D_try
     end do

    !!call InitCAMB(CMB,error)
    CMB%zre = GetZreFromTau(CMB, CMB%tau)       
  
    LastCMB(cache) = CMB
    LastParams(:,cache) = Params
    cache = mod(cache,ncache)+1

    end if
   end subroutine ParamsToCMBParams

   subroutine CMBParamsToParams(CMB, Params)
     use settings
     use cmbtypes
     implicit none
     real(mcp) Params(num_Params)
     Type(CMBParams) CMB
     real(mcp) CMBToTheta
     external CMBToTheta
 
      Params(1) = CMB%ombh2 
 
      Params(3) = CMBToTheta(CMB)*100
      Params(4) = CMB%tau
      Params(5) = CMB%omk 
      
      if (neutrino_param_mnu) then
          Params(2) = CMB%omch2
          Params(6) = CMB%omnuh2*93.04
      else
          Params(2) = CMB%omdmh2
          Params(6) = CMB%nufrac
      end if
      Params(7) = CMB%w
      Params(8) = CMB%wa
      Params(9) = CMB%nnu
      if (bbn_consistency) then
          Params(10) = 0
      else
          Params(10) = CMB%YHe
      endif
      Params(11) = CMB%iso_cdm_correlated
      Params(12) = CMB%zre_delta  
      Params(13) = CMB%ALens  
      Params(14) = CMB%fdm  
      
      Params(index_initpower:index_initpower+num_initpower-1) =CMB%InitPower(1:num_initpower) 
      Params(index_initpower + As_index-1 ) = log(CMB%InitPower(As_index))
      
      Params(index_freq:index_freq+num_freq_params-1) = CMB%data_params(1:num_freq_params)
      Params(index_nuisance:index_nuisance+num_nuisance_params-1)=CMB%nuisance(1:num_nuisance_params) 

   end subroutine CMBParamsToParams

   subroutine SetParamNames(Names)
    use settings
    use ParamNames
    Type(TParamNames) :: Names
 
    if (ParamNamesFile /='') then
      call ParamNames_init(Names, ParamNamesFile)
    else
     if (generic_mcmc) then
      Names%nnames=0
      if (Feedback>0) write (*,*) 'edit SetParamNames in params_CMB.f90 if you want to use named params'
     else
#ifdef CLIK
       call ParamNames_init(Names, trim(LocalDir)//'clik.paramnames')
#else
       call ParamNames_init(Names, trim(LocalDir)//'params_CMB.paramnames')
#endif
     end if
    end if
   end subroutine SetParamNames

 
  function CalcDerivedParams(P, derived) result (num_derived)
     use settings
     use cmbtypes
     use ParamDef
     use Lists
     implicit none
     Type(mc_real_pointer) :: derived
     Type(ParamSet) P
     Type(CMBParams) CMB
     real(mcp) r10
     integer num_derived 
     
     num_derived = 12 +  P%Theory%numderived
   
     allocate(Derived%P(num_derived))
   
      call ParamsToCMBParams(P%P,CMB)

      if (lmax_tensor /= 0 .and. compute_tensors) then
          r10 = P%Theory%cl_tensor(10,1)/P%Theory%cl(10,1)
      else
         r10 = 0
      end if

      derived%P(1) = CMB%omv
      derived%P(2) = CMB%omdm+CMB%omb
      derived%P(3) = P%Theory%Sigma_8
      derived%P(4) = CMB%zre
      derived%P(5) = r10
      derived%P(6) = CMB%H0
      derived%P(7) = P%Theory%tensor_ratio_02
      derived%P(8) = cl_norm*CMB%InitPower(As_index)*1e9
      derived%P(9) = CMB%omdmh2 + CMB%ombh2
      derived%P(10)= (CMB%omdmh2 + CMB%ombh2)*CMB%h
      derived%P(11)= CMB%Yhe !value actually used, may be set from bbn consistency
      derived%P(12)= derived%P(8)*exp(-2*CMB%tau)  !A e^{-2 tau}
      
      derived%P(13:num_derived) = P%Theory%derived_parameters(1: P%Theory%numderived)
      
  end function CalcDerivedParams
  

  subroutine WriteParams(P, mult, like)
     use settings
     use cmbtypes
     use ParamDef
     use IO
     use Lists
     implicit none
     Type(ParamSet) P
     real(mcp), intent(in) :: mult, like
     real(mcp), allocatable :: output_array(:)
     Type(mc_real_pointer) :: derived
     integer numderived 
     integer CalcDerivedParams
     external CalcDerivedParams
  
    if (outfile_handle ==0) return
  
    if (generic_mcmc) then

      call IO_OutputChainRow(outfile_handle, mult, like, P%P)
     
    else
    
      numderived = CalcDerivedParams(P, derived)

      allocate(output_array(num_real_params + numderived + nuisance_params_used ))
      output_array(1:num_real_params) =  P%P(1:num_real_params)
      output_array(num_real_params+1:num_real_params+numderived) =  derived%P
      deallocate(derived%P)

      if (nuisance_params_used>0) then
       output_array(num_real_params+numderived+1:num_real_params+numderived+nuisance_params_used) = &
        P%P(num_real_params+1:num_real_params+nuisance_params_used) 
      end if
 
      call IO_OutputChainRow(outfile_handle, mult, like, output_array)
      deallocate(output_array)           
    end if

  end  subroutine WriteParams




  subroutine WriteParamsAndDat(P, mult, like)
     use settings
     use cmbtypes
     use ParamDef
     use IO
     use Lists
     implicit none
     Type(ParamSet) P
     real(mcp), intent(in) :: mult, like
     real(mcp),allocatable :: output_array(:)
     Type(mc_real_pointer) :: derived
     integer numderived 
     integer CalcDerivedParams
     external CalcDerivedParams
         
    if (outfile_handle ==0) return

      numderived = CalcDerivedParams(P, derived)

      allocate(output_array(num_real_params + numderived + num_matter_power ))
      output_array(1:num_real_params) =  P%P(1:num_real_params)
      output_array(num_real_params+1:num_real_params+numderived) =  derived%P
      deallocate(derived%P)

      output_array(num_real_params+numderived+1:num_real_params+numderived+num_matter_power) = &
        P%Theory%matter_power(:,1) 

      call IO_OutputChainRow(outfile_handle, mult, like, output_array)
      deallocate(output_array)

  end  subroutine WriteParamsAndDat
