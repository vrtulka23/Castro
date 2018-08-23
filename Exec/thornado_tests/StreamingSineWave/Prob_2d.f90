subroutine amrex_probinit (init,name,namlen,problo,probhi) bind(c)

  use eos_module
  use eos_type_module
  use amrex_error_module 
  use network
  use probdata_module

  use amrex_fort_module, only : rt => amrex_real

  implicit none

  integer, intent(in) :: init, namlen
  integer, intent(in) :: name(namlen)
  real(rt), intent(in) :: problo(2), probhi(2)

  integer untin,i

  type (eos_t) :: eos_state

  namelist /fortin/ rho_i, T_i, rhoe_i, p_i

  !
  !     Build "probin" filename -- the name of file containing fortin namelist.
  !     
  integer, parameter :: maxlen = 256
  character probin*(maxlen)

  if (namlen .gt. maxlen) then
     call amrex_error("probin file name too long")
  end if

  do i = 1, namlen
     probin(i:i) = char(name(i))
  end do

  ! set namelist defaults

  rho_i = 1.0e6_rt
  T_i = 1.0e6_rt
  p_i = 1.0e0
  rhoe_i = 1.0e0

  !     Read namelists
  open(newunit=untin, file=probin(1:namlen), form='formatted', status='old')
  read(untin,fortin)
  close(unit=untin)

  xn(:) = 0.0e0_rt
  xn(1) = 1.0e0_rt

  eos_state%rho = rho_i
  eos_state%T = T_i
  eos_state%xn(:) = xn(:)

  call eos(eos_input_rt, eos_state)

  rhoe_i = rho_i*eos_state%e
  p_i = eos_state%p


end subroutine amrex_probinit


! ::: -----------------------------------------------------------
! ::: This routine is called at problem setup time and is used
! ::: to initialize data on each grid.  
! ::: 
! ::: NOTE:  all arrays have one cell of ghost zones surrounding
! :::        the grid interior.  Values in these cells need not
! :::        be set here.
! ::: 
! ::: INPUTS/OUTPUTS:
! ::: 
! ::: level     => amr level of grid
! ::: time      => time at which to init data             
! ::: lo,hi     => index limits of grid interior (cell centered)
! ::: nstate    => number of state components.  You should know
! :::		   this already!
! ::: state     <=  Scalar array
! ::: delta     => cell size
! ::: xlo,xhi   => physical locations of lower left and upper
! :::              right hand corner of grid.  (does not include
! :::		   ghost region).
! ::: -----------------------------------------------------------
subroutine ca_initdata(level,time,lo,hi,nscal, &
                       state,state_l1,state_l2,state_h1,state_h2, &
                       delta,xlo,xhi)

  use amrex_error_module
  use amrex_fort_module, only : rt => amrex_real
  use network, only: nspec
  use probdata_module
  use meth_params_module, only : NVAR, URHO, UMX, UMY, UEDEN, UEINT, UTEMP, UFS, UFX
  implicit none

  integer, intent(in) :: level, nscal
  integer, intent(in) :: lo(2), hi(2)
  integer, intent(in) :: state_l1,state_l2,state_h1,state_h2
  real(rt), intent(in) :: xlo(2), xhi(2), time, delta(2)
  real(rt), intent(inout) :: state(state_l1:state_h1,state_l2:state_h2,NVAR)

  integer :: i,j

  if (UFX .lt. 0.d0) &
     call amrex_abort("Must have UFX defined to run this problem!")

  do j = lo(2), hi(2)
     do i = lo(1), hi(1)

        state(i,j,URHO) = rho_i
        state(i,j,UMX) = 0.e0_rt
        state(i,j,UMY) = 0.e0_rt
        state(i,j,UEDEN) = rhoe_i
        state(i,j,UEINT) = rhoe_i
        state(i,j,UTEMP) = T_i

        state(i,j,UFS:UFS-1+nspec) = 0.0e0_rt
        state(i,j,UFS  ) = state(i,j,URHO)

        ! This is Ne
        state(i,j,UFX  ) = 1.d0
           
     enddo
  enddo

end subroutine ca_initdata

! hardwired assuming 4 moments
subroutine get_rad_ncomp(rad_ncomp) bind(C,name="ca_get_rad_ncomp")

  use RadiationFieldsModule, only : nSpecies
  use ProgramHeaderModule, only : nE, nDOF, nNodesX, nNodesE

  integer :: rad_ncomp
  integer :: n_moments = 4

  rad_ncomp =  nSpecies * n_moments * nE * nNodesX(1) *  nNodesX(2) * nNodesE

end subroutine get_rad_ncomp

! hardwired assuming 4 moments
! streaming sine wave, J = H_x = 1 + sin(2*pi*x)
subroutine ca_init_thornado_data(level,time,lo,hi,nrad_comp,rad_state, &
                                 rad_state_l1,rad_state_l2, &
                                 rad_state_h1,rad_state_h2, &
                                 delta,xlo,xhi) bind(C,name="ca_init_thornado_data")

  use probdata_module
  use RadiationFieldsModule, only : nSpecies
  use ProgramHeaderModule, only : nE, nDOF, nNodesX, nNodesE
  use amrex_fort_module, only : rt => amrex_real
  use amrex_error_module
  use amrex_constants_module, only : M_PI

  implicit none

  integer , intent(in) :: level, nrad_comp
  integer , intent(in) :: lo(2), hi(2)
  integer , intent(in) :: rad_state_l1,rad_state_h1
  integer , intent(in) :: rad_state_l2,rad_state_h2
  real(rt), intent(in) :: xlo(2), xhi(2), time, delta(2)
  real(rt), intent(inout) ::  rad_state(rad_state_l1:rad_state_h1,rad_state_l2:rad_state_h2,&
                                        0:nrad_comp-1)

  ! Local parameter
  integer, parameter :: n_moments = 4

  ! local variables
  integer :: i,j,ixnode,iynode,ienode
  integer :: ii,ii_0,is,im,ie,id
  integer :: nx,ny
  real(rt) :: xcen, ycen, xnode, ynode

  ! zero it out, just in case
  rad_state = 0.0e0_rt

  print *,'nrad_comp ',nrad_comp
  print *,'nSpecies  ',nSpecies
  print *,'n_moments ',n_moments
  print *,'nE        ',nE
  print *,'nNodesX   ',nNodesX(:)
  print *,'nNodesE   ',nNodesE
  print *,'MULT ', nSpecies * n_moments * nE * nNodesX(1) *  nNodesX(2) * nNodesE

  print *,'nDOF      ',nDOF

  ny = nNodesE*nNodesX(1)
  nx = nNodesE

  if (nDOF .ne. ny*nNodesX(2)) then
     print *,'nDOF is ', nDOF
     print *,'nNodesX(1)*nNodesX(2)*nNodesE is ', nNodesX(1)*nNodesX(2)*nNodesE
     call amrex_abort("nDOF ne nNodesX(1)*nNodesX(2)*nNodesE")
  end if
     
  do j = lo(2), hi(2)
     ycen = xlo(2) + delta(2)*(float(j-lo(2)) + 0.5e0_rt)

     do i = lo(1), hi(1)
        xcen = xlo(1) + delta(1)*(float(i-lo(1)) + 0.5e0_rt)

        do is = 1, nSpecies
        do im = 1, n_moments
        do ie = 1, nE

           ii_0 = (is-1)*(n_moments*nE*nDOF) + (im-1)*(nE*nDOF) + (ie-1)*nDOF

           do iynode = 1, nNodesX(2)
           do ixnode = 1, nNodesX(1)
           do ienode = 1, nNodesE
 
              ! calculate the indices
              id = (ienode-1) + nx*(ixnode-1) + ny*(iynode-1)
              ii = ii_0 + id

              ! calculate actual positions of the nodes used for the gaussian quadrature
              xnode = xcen + ( float(ixnode)-1.5e0_rt )*delta(1)/sqrt(3.0e0_rt)
              ynode = ycen + ( float(iynode)-1.5e0_rt )*delta(2)/sqrt(3.0e0_rt)

              ! J moment, im = 1
              if (im .eq. 1) rad_state(i,j,ii) = 1.0e0_rt + 0.9999e0_rt*sin(2.0e0_rt*M_PI*xnode)
   
              ! H_x moment, im = 2
              if (im .eq. 2) rad_state(i,j,ii) = 3.0e10_rt*0.9999e0_rt &
                              *(1.0e0_rt + 0.9999e0_rt*sin(2.0e0_rt*M_PI*xnode))
   
              ! H_y moment, im = 3
              if (im .eq. 3) rad_state(i,j,ii) = 0.0e0_rt
   
              ! H_z moment, im = 4
              if (im .eq. 4) rad_state(i,j,ii) = 0.0e0_rt
   
           end do
           end do
           end do

        end do
        end do
        end do

     enddo
  enddo

end subroutine ca_init_thornado_data


