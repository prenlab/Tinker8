c
c
c     ################################################################
c     ##  COPYRIGHT (C) 2000 by P. Bagossi, P. Ren & Jay W. Ponder  ##
c     ##                     All Rights Reserved                    ##
c     ################################################################
c
c     ###############################################################
c     ##                                                           ##
c     ##  program poledit  --  manipulate atomic multipole values  ##
c     ##                                                           ##
c     ###############################################################
c
c
c     "poledit" provides for the modification and manipulation
c     of polarizable atomic multipole electrostatic models
c
c
      program poledit
      use iounit
      use potent
      implicit none
      integer mode,idma
      integer freeunit
      logical exist,query
      character*240 string
c
c
c     get the desired type of coordinate file modification
c
      call initial
      mode = 0
      query = .true.
      call nextarg (string,exist)
      if (exist) then
         read (string,*,err=10,end=10)  mode
         query = .false.
      end if
   10 continue
      if (query) then
         write (iout,20)
   20    format (/,' The Tinker Multipole Editing Utility Can :',
     &           //,4x,'(1) Multipole Parameters from GDMA Output',
     &           /,4x,'(2) Alter Local Coordinate Frame Definitions',
     &           /,4x,'(3) Removal of Intramolecular Polarization')
         do while (mode.lt.1 .or. mode.gt.3)
            mode = 0
            write (iout,30)
   30       format (/,' Enter the Number of the Desired Choice :  ',$)
            read (input,40,err=50,end=50)  mode
   40       format (i10)
   50       continue
         end do
      end if
c
c     perform the desired multipole manipulation operation
c
      if (mode .eq. 1) then
         use_mpole = .true.
         use_polar = .true.
         idma = freeunit ()
         call readgdma (idma)
         call field
         call molsetup
         call setframe
         call rotframe
         call setpolar
         call setpgrp
         call alterpol
         call avgpole
         call prtpole
      else if (mode .eq. 2) then
         call getxyz
         call attach
         call field
         call katom
         call kmpole
         call kpolar
         call kchgtrn
         call fixframe
         call prtpole
      else if (mode .eq. 3) then
         call getxyz
         call attach
         call field
         call katom
         call kmpole
         call kpolar
         call kchgtrn
         call alterpol
         call avgpole
         call prtpole
      end if
      end
c
c
c     ##############################################################
c     ##                                                          ##
c     ##  subroutine molsetup  --  set molecule for polarization  ##
c     ##                                                          ##
c     ##############################################################
c
c
c     "molsetup" generates trial parameters needed to perform
c     polarizable multipole calculations on a structure read
c     from distributed multipole analysis output
c
c
      subroutine molsetup
      use atomid
      use atoms
      use couple
      use files
      use kpolr
      use mpole
      use polar
      use ptable
      implicit none
      integer i,j
      integer atn,size
      real*8 xi,yi,zi
      real*8 xr,yr,zr
      real*8 ri,rij,dij
      real*8, allocatable :: rad(:)
c
c
c     perform dynamic allocation of some local arrays
c
      allocate (rad(n))
c
c     set base atomic radii from covalent radius values
c
      do i = 1, n
         rad(i) = 0.76d0
         atn = atomic(i)
         if (atn .ne. 0)  rad(i) = covrad(atn)
         if (atn .eq. 1) then
            rad(i) = 1.25d0 * rad(i)
         else if (atn .eq. 9) then
            rad(i) = 1.25d0 * rad(i)
         else
            rad(i) = 1.15d0 * rad(i)
         end if
      end do
c
c     assign atom connectivities based on interatomic distances
c
      do i = 1, n
         n12(i) = 0
         do j = 1, maxval
            i12(j,i) = 0
         end do
      end do
      do i = 1, n-1
         xi = x(i)
         yi = y(i)
         zi = z(i)
         ri = rad(i)
         do j = i+1, n
            xr = x(j) - xi
            yr = y(j) - yi
            zr = z(j) - zi
            rij = ri + rad(j)
            dij = sqrt(xr*xr + yr*yr + zr*zr)
            if (dij .lt. rij) then
               n12(i) = n12(i) + 1
               i12(n12(i),i) = j
               n12(j) = n12(j) + 1
               i12(n12(j),j) = i
            end if
         end do
      end do
      do i = 1, n
         call sort (n12(i),i12(1,i))
      end do
c
c     find the bonds, angles, torsions and small rings
c
      call attach
      call bonds
      call angles
      call torsions
      call bitors
      call rings
c
c     perform deallocation of some local arrays
c
      deallocate (rad)
c
c     assign unique atom types and set the valence values
c
      size = min(24,leng)
      do i = 1, n
         type(i) = i
         valence(i) = n12(i)
         story(i) = filename(1:size)
      end do
c
c     assign the standard atomic weight by atomic number
c
      do i = 1, n
         mass(i) = 1.0d0
         atn = atomic(i)
         if (atn .ne. 0)  mass(i) = atmass(atn)
      end do
c
c     perform dynamic allocation of some global arrays
c
      if (.not. allocated(ipole))  allocate (ipole(n))
      if (.not. allocated(polsiz))  allocate (polsiz(n))
      if (.not. allocated(pollist))  allocate (pollist(n))
c
c     set atomic multipole sites and polarizability indices
c
      npole = n
      npolar = n
      do i = 1, n
         ipole(i) = i
         polsiz(i) = 13
         pollist(i) = i
      end do
c
c     zero out polarization group membership by atom type
c
      do i = 1, maxtyp
         do j = 1, maxval
            pgrp(j,i) = 0
         end do
      end do
      return
      end
c
c
c     ###############################################################
c     ##                                                           ##
c     ##  subroutine setframe  --  define local coordinate frames  ##
c     ##                                                           ##
c     ###############################################################
c
c
c     "setframe" assigns a local coordinate frame at each atomic
c     multipole site using high priority connected atoms along axes
c
c
      subroutine setframe
      use atomid
      use atoms
      use couple
      use iounit
      use mpole
      implicit none
      integer i,j,m
      integer ia,ib,ic,id
      integer ka,kb,kc,ki
      integer mab,mac,mbc
      integer mad,mbd,mcd
      integer mabc,mabd
      integer macd,mbcd
      integer priority
      real*8 geometry
      logical exist,query
      logical change
      logical noinvert
      logical pyramid
      character*240 record
      character*240 string
c
c
c     perform dynamic allocation of some global arrays
c
      if (.not. allocated(zaxis))  allocate (zaxis(npole))
      if (.not. allocated(xaxis))  allocate (xaxis(npole))
      if (.not. allocated(yaxis))  allocate (yaxis(npole))
      if (.not. allocated(polaxe))  allocate (polaxe(npole))
c
c     initialize the local frame type and defining atoms
c
      do i = 1, npole
         polaxe(i) = 'None'
         zaxis(i) = 0
         xaxis(i) = 0
         yaxis(i) = 0
      end do
c
c     set true if pyramidal trivalent nitrogen cannot invert
c
      noinvert = .true.
c
c     assign the local frame definition for an isolated atom
c
      do i = 1, npole
         j = n12(i)
         if (j .eq. 0) then
            polaxe(i) = 'None'
            zaxis(i) = 0
            xaxis(i) = 0
            yaxis(i) = 0
c
c     assign the local frame definition for a monovalent atom
c
         else if (j .eq. 1) then
            polaxe(i) = 'Z-Only'
            zaxis(i) = ia
            xaxis(i) = 0
            yaxis(i) = 0
            ia = i12(1,i)
            call frame13 (i,ia,noinvert)
c
c     assign the local frame definition for a divalent atom
c
         else if (j .eq. 2) then
            ia = i12(1,i)
            ib = i12(2,i)
            ki = atomic(i)
            yaxis(i) = 0
            m = priority (i,ia,ib,0)
            if (ki .eq. 6) then
               polaxe(i) = 'Z-Only'
               zaxis(i) = m
               if (m .eq. 0)  zaxis(i) = ia
               xaxis(i) = 0
            else if (m .eq. ia) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ia
               xaxis(i) = ib
            else if (m .eq. ib) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ib
               xaxis(i) = ia
            else
               polaxe(i) = 'Bisector'
               zaxis(i) = ia
               xaxis(i) = ib
            end if
c
c     assign the local frame definition for a trivalent atom
c
         else if (j .eq. 3) then
            ia = i12(1,i)
            ib = i12(2,i)
            ic = i12(3,i)
            ki = atomic(i)
            ka = atomic(ia)
            kb = atomic(ib)
            kc = atomic(ic)
            mab = priority (i,ia,ib,0)
            mac = priority (i,ia,ic,0)
            mbc = priority (i,ib,ic,0)
            mabc = priority (i,ia,ib,ic)
            if (mabc .eq. 0) then
               polaxe(i) = 'None'
               zaxis(i) = 0
               xaxis(i) = 0
               yaxis(i) = 0
               pyramid = (abs(geometry(ia,i,ib,ic)) .lt. 135.0d0)
               pyramid = (pyramid .and. noinvert)
               if (ki.eq.7 .and. pyramid) then
                  polaxe(i) = '3-Fold'
                  zaxis(i) = ia
                  xaxis(i) = ib
                  yaxis(i) = ic
               else if (ki.eq.15 .or. ki.eq.16) then
                  polaxe(i) = '3-Fold'
                  zaxis(i) = ia
                  xaxis(i) = ib
                  yaxis(i) = ic
               end if
            else if (mab.eq.0 .and. kb.ge.kc) then
               polaxe(i) = 'Bisector'
               zaxis(i) = ia
               xaxis(i) = ib
               yaxis(i) = 0
            else if (mac.eq.0 .and. ka.ge.kb) then
               polaxe(i) = 'Bisector'
               zaxis(i) = ia
               xaxis(i) = ic
               yaxis(i) = 0
            else if (mbc.eq.0 .and. kc.ge.ka) then
               polaxe(i) = 'Bisector'
               zaxis(i) = ib
               xaxis(i) = ic
               yaxis(i) = 0
            else if (mabc .eq. ia) then
               polaxe(i) = 'Z-Only'
               zaxis(i) = ia
               xaxis(i) = 0
               yaxis(i) = 0
               pyramid = (abs(geometry(ia,i,ib,ic)) .lt. 135.0d0)
               pyramid = (pyramid .and. noinvert)
               if (mbc .eq. ib) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ib
               else if (mbc .eq. ic) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ic
               else if (ki .eq. 6) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ib
               else if (ki.eq.7 .and. pyramid) then
                  polaxe(i) = 'Z-Bisect'
                  xaxis(i) = ib
                  yaxis(i) = ic
               else if (ki.eq.7 .and. .not.pyramid) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ib
               else if (ki.eq.15 .or. ki.eq.16) then
                  polaxe(i) = 'Z-Bisect'
                  xaxis(i) = ib
                  yaxis(i) = ic
               else
                  call frame13 (i,ia,noinvert)
               end if
            else if (mabc .eq. ib) then
               polaxe(i) = 'Z-Only'
               zaxis(i) = ib
               xaxis(i) = 0
               yaxis(i) = 0
               pyramid = (abs(geometry(ib,i,ia,ic)) .lt. 135.0d0)
               pyramid = (pyramid .and. noinvert)
               if (mac .eq. ia) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ia
               else if (mac .eq. ic) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ic
               else if (ki .eq. 6) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ia
               else if (ki.eq.7 .and. pyramid) then
                  polaxe(i) = 'Z-Bisect'
                  xaxis(i) = ia
                  yaxis(i) = ic
               else if (ki.eq.7 .and. .not.pyramid) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ia
               else if (ki.eq.15 .or. ki.eq.16) then
                  polaxe(i) = 'Z-Bisect'
                  xaxis(i) = ia
                  yaxis(i) = ic
               else
                  call frame13 (i,ib,noinvert)
               end if
            else if (mabc .eq. ic) then
               polaxe(i) = 'Z-Only'
               zaxis(i) = ic
               xaxis(i) = 0
               yaxis(i) = 0
               pyramid = (abs(geometry(ic,i,ia,ib)) .lt. 135.0d0)
               pyramid = (pyramid .and. noinvert)
               if (mab .eq. ia) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ia
               else if (mab .eq. ib) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ib
               else if (ki .eq. 6) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ia
               else if (ki.eq.7 .and. pyramid) then
                  polaxe(i) = 'Z-Bisect'
                  xaxis(i) = ia
                  yaxis(i) = ib
               else if (ki.eq.7 .and. .not.pyramid) then
                  polaxe(i) = 'Z-then-X'
                  xaxis(i) = ia
               else if (ki.eq.15 .or. ki.eq.16) then
                  polaxe(i) = 'Z-Bisect'
                  xaxis(i) = ia
                  yaxis(i) = ib
               else
                  call frame13 (i,ic,noinvert)
               end if
            end if
c
c     assign the local frame definition for a tetravalent atom
c
         else if (j .eq. 4) then
            ia = i12(1,i)
            ib = i12(2,i)
            ic = i12(3,i)
            id = i12(4,i)
            mab = priority (i,ia,ib,0)
            mac = priority (i,ia,ic,0)
            mbc = priority (i,ib,ic,0)
            mad = priority (i,ia,id,0)
            mbd = priority (i,ib,id,0)
            mcd = priority (i,ic,id,0)
            mabc = priority (i,ia,ib,ic)
            mabd = priority (i,ia,ib,id)
            macd = priority (i,ia,ic,id)
            mbcd = priority (i,ib,ic,id)
            if (mabc.eq.0 .and. mbcd.eq.0) then
               polaxe(i) = 'None'
               zaxis(i) = 0
               xaxis(i) = 0
               yaxis(i) = 0
            else if (mabc.eq.ia .and. mabd.eq.ia) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ia
               yaxis(i) = 0
               if (mbcd .ne. 0) then
                  xaxis(i) = mbcd
               else
                  call frame13 (i,ia,noinvert)
               end if
            else if (mabc.eq.ib .and. mabd.eq.ib) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ib
               yaxis(i) = 0
               if (macd .ne. 0) then
                  xaxis(i) = macd
               else
                  call frame13 (i,ib,noinvert)
               end if
            else if (mabc.eq.ia .and. macd.eq.ia) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ia
               yaxis(i) = 0
               if (mbcd .ne. 0) then
                  xaxis(i) = mbcd
               else
                  call frame13 (i,ia,noinvert)
               end if
            else if (mabc.eq.ic .and. macd.eq.ic) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ic
               yaxis(i) = 0
               if (mabd .ne. 0) then
                  xaxis(i) = mabd
               else
                  call frame13 (i,ic,noinvert)
               end if
            else if (mabc.eq.ib .and. mbcd.eq.ib) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ib
               yaxis(i) = 0
               if (macd .ne. 0) then
                  xaxis(i) = macd
               else
                  call frame13 (i,ib,noinvert)
               end if
            else if (mabc.eq.ic .and. mbcd.eq.ic) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ic
               yaxis(i) = 0
               if (mabd .ne. 0) then
                  xaxis(i) = mabd
               else
                  call frame13 (i,ic,noinvert)
               end if
            else if (mabd.eq.ia .and. macd.eq.ia) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ia
               yaxis(i) = 0
               if (mbcd .ne. 0) then
                  xaxis(i) = mbcd
               else
                  call frame13 (i,ia,noinvert)
               end if
            else if (mabd.eq.id .and. macd.eq.id) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = id
               yaxis(i) = 0
               if (mabc .ne. 0) then
                  xaxis(i) = mabc
               else
                  call frame13 (i,id,noinvert)
               end if
            else if (mabd.eq.ib .and. mbcd.eq.ib) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ib
               yaxis(i) = 0
               if (macd .ne. 0) then
                  xaxis(i) = macd
               else
                  call frame13 (i,ib,noinvert)
               end if
            else if (mabd.eq.id .and. mbcd.eq.id) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = id
               yaxis(i) = 0
               if (mabc .ne. 0) then
                  xaxis(i) = mabc
               else
                  call frame13 (i,id,noinvert)
               end if
            else if (macd.eq.ic .and. mbcd.eq.ic) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = ic
               yaxis(i) = 0
               if (mabd .ne. 0) then
                  xaxis(i) = mabd
               else
                  call frame13 (i,ic,noinvert)
               end if
            else if (macd.eq.id .and. mbcd.eq.id) then
               polaxe(i) = 'Z-then-X'
               zaxis(i) = id
               yaxis(i) = 0
               if (mabc .ne. 0) then
                  xaxis(i) = mabc
               else
                  call frame13 (i,id,noinvert)
               end if
            else if (mbcd .eq. 0) then
               polaxe(i) = 'Z-Only'
               zaxis(i) = ia
               xaxis(i) = 0
               yaxis(i) = 0
               call frame13 (i,ia,noinvert)
            else if (macd .eq. 0) then
               polaxe(i) = 'Z-Only'
               zaxis(i) = ib
               xaxis(i) = 0
               yaxis(i) = 0
               call frame13 (i,ib,noinvert)
            else if (mabd .eq. 0) then
               polaxe(i) = 'Z-Only'
               zaxis(i) = ic
               xaxis(i) = 0
               yaxis(i) = 0
               call frame13 (i,ic,noinvert)
            else if (mabc .eq. 0) then
               polaxe(i) = 'Z-Only'
               zaxis(i) = id
               xaxis(i) = 0
               yaxis(i) = 0
               call frame13 (i,id,noinvert)
            else if (mab.eq.0 .and. mcd.eq.0) then
               if (mac .eq. ia) then
                  polaxe(i) = 'Bisector'
                  zaxis(i) = ia
                  xaxis(i) = ib
                  yaxis(i) = 0
               else if (mac .eq. ic) then
                  polaxe(i) = 'Bisector'
                  zaxis(i) = ic
                  xaxis(i) = id
                  yaxis(i) = 0
               end if
            else if (mac.eq.0 .and. mbd.eq.0) then
               if (mab .eq. ia) then
                  polaxe(i) = 'Bisector'
                  zaxis(i) = ia
                  xaxis(i) = ic
                  yaxis(i) = 0
               else if (mab .eq. ib) then
                  polaxe(i) = 'Bisector'
                  zaxis(i) = ib
                  xaxis(i) = id
                  yaxis(i) = 0
               end if
            else if (mad.eq.0 .and. mbc.eq.0) then
               if (mab .eq. ia) then
                  polaxe(i) = 'Bisector'
                  zaxis(i) = ia
                  xaxis(i) = id
                  yaxis(i) = 0
               else if (mab .eq. ib) then
                  polaxe(i) = 'Bisector'
                  zaxis(i) = ib
                  xaxis(i) = ic
                  yaxis(i) = 0
               end if
            else if (mab .eq. 0) then
               polaxe(i) = 'Z-Bisect'
               zaxis(i) = mcd
               xaxis(i) = ia
               yaxis(i) = ib
            else if (mac .eq. 0) then
               polaxe(i) = 'Z-Bisect'
               zaxis(i) = mbd
               xaxis(i) = ia
               yaxis(i) = ic
            else if (mad .eq. 0) then
               polaxe(i) = 'Z-Bisect'
               zaxis(i) = mbc
               xaxis(i) = ia
               yaxis(i) = id
            else if (mbc .eq. 0) then
               polaxe(i) = 'Z-Bisect'
               zaxis(i) = mad
               xaxis(i) = ib
               yaxis(i) = ic
            else if (mbd .eq. 0) then
               polaxe(i) = 'Z-Bisect'
               zaxis(i) = mac
               xaxis(i) = ib
               yaxis(i) = id
            else if (mcd .eq. 0) then
               polaxe(i) = 'Z-Bisect'
               zaxis(i) = mab
               xaxis(i) = ic
               yaxis(i) = id
            end if
         end if
      end do
c
c     list the local frame definition for each multipole site
c
      write (iout,10)
   10 format (/,' Local Frame Definition for Multipole Sites :')
      write (iout,20)
   20 format (/,5x,'Atom',5x,'Name',6x,'Axis Type',5x,'Z Axis',
     &           2x,'X Axis',2x,'Y Axis',/)
      do i = 1, npole
         write (iout,30)  i,name(i),polaxe(i),zaxis(i),
     &                    xaxis(i),yaxis(i)
   30    format (i8,6x,a3,7x,a8,2x,3i8)
      end do
c
c     allow the user to manually alter local coordinate frames
c
      change = .false.
      query = .true.
      i = -1
      call nextarg (string,exist)
      if (exist) then
         read (string,*,err=40,end=40)  i
         if (i .eq. 0)  query = .false.
      end if
   40 continue
      do while (query)
         i = 0
         ia = 0
         ib = 0
         ic = 0
         write (iout,50)
   50    format (/,' Enter Altered Local Frame Definition',
     &              ' [<Enter>=Exit] :  ',$)
         read (input,60)  record
   60    format (a240)
         read (record,*,err=70,end=70)  i,ia,ib,ic
   70    continue
         if (i .eq. 0) then
            query = .false.
         else
            change = .true.
            if (ia .eq. 0)  polaxe(i)= 'None'
            if (ia.ne.0 .and. ib.eq.0)  polaxe(i) = 'Z-Only'
            if (ia.gt.0 .and. ib.gt.0)  polaxe(i) = 'Z-then-X'
            if (ia.lt.0 .or. ib.lt.0)  polaxe(i) = 'Bisector'
            if (ib.lt.0 .and. ic.lt.0)  polaxe(i) = 'Z-Bisect'
            if (max(ia,ib,ic) .lt. 0)  polaxe(i) = '3-Fold'
            zaxis(i) = abs(ia)
            xaxis(i) = abs(ib)
            yaxis(i) = abs(ic)
         end if
      end do
c
c     repeat local frame list if definitions were altered
c
      if (change) then
         write (iout,80)
   80    format (/,' Local Frame Definition for Multipole Sites :')
         write (iout,90)
   90    format (/,5x,'Atom',5x,'Name',6x,'Axis Type',5x,'Z Axis',
     &              2x,'X Axis',2x,'Y Axis',/)
         do i = 1, npole
            write (iout,100)  i,name(i),polaxe(i),zaxis(i),
     &                        xaxis(i),yaxis(i)
  100       format (i8,6x,a3,7x,a8,2x,3i8)
         end do
      end if
      return
      end
c
c
c     ##################################################################
c     ##                                                              ##
c     ##  subroutine frame13  --  set local axis via 1-3 attachments  ##
c     ##                                                              ##
c     ##################################################################
c
c
c     "frame13" finds local coordinate frame defining atoms in cases
c     where the use of 1-3 connected atoms is required
c
c
      subroutine frame13 (i,ia,noinvert)
      use atomid
      use couple
      use mpole
      implicit none
      integer i,ia
      integer ib,ic,id
      integer k,ka,m
      integer priority
      real*8 geometry
      logical noinvert
      logical pyramid
c
c
c     get atoms directly adjacent to the primary connected atom
c
      ib = 0
      ic = 0
      id = 0
      ka = atomic(ia)
      do k = 1, n12(ia)
         m = i12(k,ia)
         if (m .ne. i) then
            if (ib .eq. 0) then
               ib = m
            else if (ic .eq. 0) then
               ic = m
            else if (id .eq. 0) then
               id = m
            end if
         end if
      end do
c
c     case with no atoms attached 1-3 through primary connection
c
      if (n12(ia) .eq. 1) then
         polaxe(i) = 'Z-Only'
         zaxis(i) = ia
         xaxis(i) = 0
         yaxis(i) = 0
c
c     only one atom is attached 1-3 through primary connection
c
      else if (n12(ia) .eq. 2) then
         polaxe(i) = 'Z-then-X'
         zaxis(i) = ia
         xaxis(i) = ib
         yaxis(i) = 0
         if (ka .eq. 6) then
            polaxe(i) = 'Z-Only'
            xaxis(i) = 0
         end if
c
c     two atoms are attached 1-3 through primary connection
c
      else if (n12(ia) .eq. 3) then
         polaxe(i) = 'Z-Only'
         zaxis(i) = ia
         xaxis(i) = 0
         yaxis(i) = 0
         pyramid = (abs(geometry(i,ia,ib,ic)) .lt. 135.0d0)
         m = priority (ia,ib,ic,0)
         if (m .ne. 0) then
            polaxe(i) = 'Z-then-X'
            xaxis(i) = m
         else if (ka .eq. 6) then
            polaxe(i) = 'Z-then-X'
            xaxis(i) = ib
         else if (ka.eq.7 .and. pyramid .and. noinvert) then
            polaxe(i) = 'Z-Bisect'
            xaxis(i) = ib
            yaxis(i) = ic
         else if (ka.eq.7 .and. .not.pyramid) then
            polaxe(i) = 'Z-then-X'
            xaxis(i) = ib
         else if (ka.eq.15 .or. ka.eq.16) then
            polaxe(i) = 'Z-Bisect'
            xaxis(i) = ib
            yaxis(i) = ic
         end if
c
c     three atoms are attached 1-3 through primary connection
c
      else if (n12(ia) .eq. 4) then
         polaxe(i) = 'Z-Only'
         zaxis(i) = ia
         xaxis(i) = 0
         yaxis(i) = 0
         m = priority (ia,ib,ic,id)
         if (m .ne. 0) then
            polaxe(i) = 'Z-then-X'
            xaxis(i) = m
         end if
      end if
      return
      end
c
c
c     ################################################################
c     ##                                                            ##
c     ##  function priority  --  atom priority for axis assignment  ##
c     ##                                                            ##
c     ################################################################
c
c
c     "priority" decides which of a set of connected atoms should
c     have highest priority in construction of a local coordinate
c     frame and returns its atom number; if all atoms are of equal
c     priority then zero is returned
c
c
      function priority (i,ia,ib,ic)
      use atomid
      use couple
      implicit none
      integer i,j
      integer nlink
      integer ia,ib,ic
      integer ja,jb,jc
      integer ka,kb,kc
      integer ma,mb,mc
      integer priority
c
c
c     get info on sites to consider for priority assignment
c
      priority = 0
      nlink = 0
      if (ia .gt. 0) then
         nlink = nlink + 1
         ja = n12(ia)
         ka = atomic(ia)
      end if
      if (ib .gt. 0) then
         nlink = nlink + 1
         jb = n12(ib)
         kb = atomic(ib)
      end if
      if (ic .gt. 0) then
         nlink = nlink + 1
         jc = n12(ic)
         kc = atomic(ic)
      end if
c
c     for only one linked atom, it has the highest priority
c
      if (nlink .eq. 1) then
         priority = ia
      end if
c
c     for two linked atoms, find the one with highest priority
c
      if (nlink .eq. 2) then
         if (ka .gt. kb) then
            priority = ia
         else if (kb .gt. ka) then
            priority = ib
         else
            if (ja .lt. jb) then
               priority = ia
            else if (jb .lt. ja) then
               priority = ib
            else
               ma = 0
               mb = 0
               do j = 1, ja
                  ma = ma + atomic(i12(j,ia))
                  mb = mb + atomic(i12(j,ib))
               end do
               if (ma .gt. mb) then
                  priority = ia
               else if (mb .gt. ma) then
                  priority = ib
               else
                  ma = 0
                  mb = 0
                  do j = 1, n13(ia)
                     ma = ma + atomic(i13(j,ia))
                  end do
                  do j = 1, n13(ib)
                     mb = mb + atomic(i13(j,ib))
                  end do
                  if (ma .gt. mb) then
                     priority = ia
                  else if (mb .gt. ma) then
                     priority = ib
                  else
                     ma = 0
                     mb = 0
                     do j = 1, n14(ia)
                        ma = ma + atomic(i14(j,ia))
                     end do
                     do j = 1, n14(ib)
                        mb = mb + atomic(i14(j,ib))
                     end do
                     if (ma .gt. mb) then
                        priority = ia
                     else if (mb .gt. ma) then
                        priority = ib
                     else
                        ma = 0
                        mb = 0
                        do j = 1, n15(ia)
                           ma = ma + atomic(i15(j,ia))
                        end do
                        do j = 1, n15(ib)
                           mb = mb + atomic(i15(j,ib))
                        end do
                        if (ma .gt. mb) then
                           priority = ia
                        else if (mb .gt. ma) then
                           priority = ib
                        else
                           priority = 0
                        end if
                     end if
                  end if
               end if
            end if
         end if
      end if
c
c     for three linked atoms, find the one with highest priority
c
      if (nlink .eq. 3) then
         if (ka.gt.kb .and. ka.gt.kc) then
            priority = ia
         else if (kb.gt.ka .and. kb.gt.kc) then
            priority = ib
         else if (kc.gt.ka .and. kc.gt.kb) then
            priority = ic
         else if (ka.eq.kb .and. kc.lt.ka) then
            if (ja .lt. jb) then
               priority = ia
            else if (jb .lt. ja) then
               priority = ib
            else
               ma = 0
               mb = 0
               do j = 1, ja
                  ma = ma + atomic(i12(j,ia))
                  mb = mb + atomic(i12(j,ib))
               end do
               if (ma .gt. mb) then
                  priority = ia
               else if (mb .gt. ma) then
                  priority = ib
               else
                  ma = 0
                  mb = 0
                  do j = 1, n13(ia)
                     ma = ma + atomic(i13(j,ia))
                  end do
                  do j = 1, n13(ib)
                     mb = mb + atomic(i13(j,ib))
                  end do
                  if (ma .gt. mb) then
                     priority = ia
                  else if (mb .gt. ma) then
                     priority = ib
                  else
                     ma = 0
                     mb = 0
                     do j = 1, n14(ia)
                        ma = ma + atomic(i14(j,ia))
                     end do
                     do j = 1, n14(ib)
                        mb = mb + atomic(i14(j,ib))
                     end do
                     if (ma .gt. mb) then
                        priority = ia
                     else if (mb .gt. ma) then
                        priority = ib
                     else
                        ma = 0
                        mb = 0
                        do j = 1, n15(ia)
                           ma = ma + atomic(i15(j,ia))
                        end do
                        do j = 1, n15(ib)
                           mb = mb + atomic(i15(j,ib))
                        end do
                        if (ma .gt. mb) then
                           priority = ia
                        else if (mb .gt. ma) then
                           priority = ib
                        else
                           priority = ic
                        end if
                     end if
                  end if
               end if
            end if
         else if (ka.eq.kc .and. kb.lt.kc) then
            if (ja .lt. jc) then
               priority = ia
            else if (jc .lt. ja) then
               priority = ic
            else
               ma = 0
               mc = 0
               do j = 1, ja
                  ma = ma + atomic(i12(j,ia))
                  mc = mc + atomic(i12(j,ic))
               end do
               if (ma .gt. mc) then
                  priority = ia
               else if (mc .gt. ma) then
                  priority = ic
               else
                  ma = 0
                  mc = 0
                  do j = 1, n13(ia)
                     ma = ma + atomic(i13(j,ia))
                  end do
                  do j = 1, n13(ic)
                     mc = mc + atomic(i13(j,ic))
                  end do
                  if (ma .gt. mc) then
                     priority = ia
                  else if (mc .gt. ma) then
                     priority = ic
                  else
                     ma = 0
                     mc = 0
                     do j = 1, n14(ia)
                        ma = ma + atomic(i14(j,ia))
                     end do
                     do j = 1, n14(ic)
                        mc = mc + atomic(i14(j,ic))
                     end do
                     if (ma .gt. mc) then
                        priority = ia
                     else if (mc .gt. ma) then
                        priority = ic
                     else
                        ma = 0
                        mc = 0
                        do j = 1, n15(ia)
                           ma = ma + atomic(i15(j,ia))
                        end do
                        do j = 1, n15(ic)
                           mc = mc + atomic(i15(j,ic))
                        end do
                        if (ma .gt. mc) then
                           priority = ia
                        else if (mc .gt. ma) then
                           priority = ic
                        else
                           priority = ib
                        end if
                     end if
                  end if
               end if
            end if
         else if (kb.eq.kc .and. ka.lt.kb) then
            if (jb .lt. jc) then
               priority = ib
            else if (jc .lt. jb) then
               priority = ic
            else
               mb = 0
               mc = 0
               do j = 1, jb
                  mb = mb + atomic(i12(j,ib))
                  mc = mc + atomic(i12(j,ic))
               end do
               if (mb .gt. mc) then
                  priority = ib
               else if (mc .gt. mb) then
                  priority = ic
               else
                  mb = 0
                  mc = 0
                  do j = 1, n13(ib)
                     mb = mb + atomic(i13(j,ib))
                  end do
                  do j = 1, n13(ic)
                     mc = mc + atomic(i13(j,ic))
                  end do
                  if (mb .gt. mc) then
                     priority = ia
                  else if (mc .gt. mb) then
                     priority = ic
                  else
                     mb = 0
                     mc = 0
                     do j = 1, n14(ib)
                        mb = mb + atomic(i14(j,ib))
                     end do
                     do j = 1, n14(ic)
                        mc = mc + atomic(i14(j,ic))
                     end do
                     if (mb .gt. mc) then
                        priority = ia
                     else if (mc .gt. mb) then
                        priority = ic
                     else
                        mb = 0
                        mc = 0
                        do j = 1, n15(ib)
                           mb = mb + atomic(i15(j,ib))
                        end do
                        do j = 1, n15(ic)
                           mc = mc + atomic(i15(j,ic))
                        end do
                        if (mb .gt. mc) then
                           priority = ia
                        else if (mc .gt. mb) then
                           priority = ic
                        else
                           priority = ia
                        end if
                     end if
                  end if
               end if
            end if
         else
            if (ja.gt.jb.and.ja.gt.jc) then
               priority = ia
            else if (jb.gt.ja .and. jb.gt.jc) then
               priority = ib
            else if (jc.gt.ja .and. jc.gt.jb) then
               priority = ic
            else if (ja.lt.jb .and. ja.lt.jc) then
               priority = ia
            else if (jb.lt.ja .and. jb.lt.jc) then
               priority = ib
            else if (jc.lt.ja .and. jc.lt.jb) then
               priority = ic
            else
               ma = 0
               mb = 0
               mc = 0
               do j = 1, ja
                  ma = ma + atomic(i12(j,ia))
                  mb = mb + atomic(i12(j,ib))
                  mc = mc + atomic(i12(j,ic))
               end do
               if (ma.gt.mb .and. ma.gt.mc) then
                  priority = ia
               else if (mb.gt.ma .and. mb.gt.mc) then
                  priority = ib
               else if (mc.gt.ma .and. mc.gt.mb) then
                  priority = ic
               else if (ma.lt.mb .and. ma.lt.mc) then
                  priority = ia
               else if (mb.lt.ma .and. mb.lt.mc) then
                  priority = ib
               else if (mc.lt.ma .and. mc.lt.mb) then
                  priority = ic
               else
                  ma = 0
                  mb = 0
                  mc = 0
                  do j = 1, n13(ia)
                     ma = ma + atomic(i13(j,ia))
                  end do
                  do j = 1, n13(ib)
                     mb = mb + atomic(i13(j,ib))
                  end do
                  do j = 1, n13(ic)
                     mc = mc + atomic(i13(j,ic))
                  end do
                  if (ma.gt.mb .and. ma.gt.mc) then
                     priority = ia
                  else if (mb.gt.ma .and. mb.gt.mc) then
                     priority = ib
                  else if (mc.gt.ma .and. mc.gt.mb) then
                     priority = ic
                  else if (ma.lt.mb .and. ma.lt.mc) then
                     priority = ia
                  else if (mb.lt.ma .and. mb.lt.mc) then
                     priority = ib
                  else if (mc.lt.ma .and. mc.lt.mb) then
                     priority = ic
                  else
                     ma = 0
                     mb = 0
                     mc = 0
                     do j = 1, n14(ia)
                        ma = ma + atomic(i14(j,ia))
                     end do
                     do j = 1, n14(ib)
                        mb = mb + atomic(i14(j,ib))
                     end do
                     do j = 1, n14(ic)
                        mc = mc + atomic(i14(j,ic))
                     end do
                     if (ma.gt.mb .and. ma.gt.mc) then
                        priority = ia
                     else if (mb.gt.ma .and. mb.gt.mc) then
                        priority = ib
                     else if (mc.gt.ma .and. mc.gt.mb) then
                        priority = ic
                     else if (ma.lt.mb .and. ma.lt.mc) then
                        priority = ia
                     else if (mb.lt.ma .and. mb.lt.mc) then
                        priority = ib
                     else if (mc.lt.ma .and. mc.lt.mb) then
                        priority = ic
                     else
                        ma = 0
                        mb = 0
                        mc = 0
                        do j = 1, n15(ia)
                           ma = ma + atomic(i15(j,ia))
                        end do
                        do j = 1, n15(ib)
                           mb = mb + atomic(i15(j,ib))
                        end do
                        do j = 1, n15(ic)
                           mc = mc + atomic(i15(j,ic))
                        end do
                        if (ma.gt.mb .and. ma.gt.mc) then
                           priority = ia
                        else if (mb.gt.ma .and. mb.gt.mc) then
                           priority = ib
                        else if (mc.gt.ma .and. mc.gt.mb) then
                           priority = ic
                        else if (ma.lt.mb .and. ma.lt.mc) then
                           priority = ia
                        else if (mb.lt.ma .and. mb.lt.mc) then
                           priority = ib
                        else if (mc.lt.ma .and. mc.lt.mb) then
                           priority = ic
                        else
                           priority = 0
                        end if
                     end if
                  end if
               end if
            end if
         end if
      end if
      return
      end
c
c
c     ##################################################################
c     ##                                                              ##
c     ##  subroutine rotframe  --  convert multipoles to local frame  ##
c     ##                                                              ##
c     ##################################################################
c
c
c     "rotframe" takes the global multipole moments and rotates them
c     into the local coordinate frame defined at each atomic site
c
c
      subroutine rotframe
      use atomid
      use atoms
      use inform
      use iounit
      use mpole
      use units
      implicit none
      integer i,j,k
      integer ia,ib,ic,id
      integer xaxe,yaxe,zaxe
      real*8 xad,yad,zad
      real*8 xbd,ybd,zbd
      real*8 xcd,ycd,zcd
      real*8 c1,c2,c3,vol
      logical check
c
c
c     perform dynamic allocation of some global arrays
c
      if (.not. allocated(pole))  allocate (pole(maxpole,n))
      if (.not. allocated(rpole))  allocate (rpole(maxpole,n))
c
c     rotate the multipoles from global frame to local frame
c
      call rotrpole
c
c     check the sign of multipole components at chiral sites;
c     note "yaxis" sign is not flipped based on signed volume
c
      do i = 1, npole
         check = .true.
         if (polaxe(i) .ne. 'Z-then-X')  check = .false.
         if (yaxis(i) .eq. 0)  check = .false.
         if (check) then
            ia = ipole(i)
            ib = zaxis(i)
            ic = xaxis(i)
            id = yaxis(i)
            xad = x(ia) - x(id)
            yad = y(ia) - y(id)
            zad = z(ia) - z(id)
            xbd = x(ib) - x(id)
            ybd = y(ib) - y(id)
            zbd = z(ib) - z(id)
            xcd = x(ic) - x(id)
            ycd = y(ic) - y(id)
            zcd = z(ic) - z(id)
            c1 = ybd*zcd - zbd*ycd
            c2 = ycd*zad - zcd*yad
            c3 = yad*zbd - zad*ybd
            vol = xad*c1 + xbd*c2 + xcd*c3
            if (vol .lt. 0.0d0) then
               pole(3,i) = -pole(3,i)
               pole(6,i) = -pole(6,i)
               pole(8,i) = -pole(8,i)
               pole(10,i) = -pole(10,i)
               pole(12,i) = -pole(12,i)
            end if
         end if
      end do
c
c     convert dipole and quadrupole moments back to atomic units
c
      do i = 1, npole
         rpole(1,i) = pole(1,i)
         do j = 2, 4
            rpole(j,i) = pole(j,i) / bohr
         end do
         do j = 5, 13
            rpole(j,i) = 3.0d0 * pole(j,i) / bohr**2
         end do
      end do
c
c     print the local frame Cartesian atomic multipoles
c
      if (verbose) then
         write (iout,10)
   10    format (/,' Local Frame Cartesian Multipole Moments :')
         do i = 1, n
            k = pollist(i)
            if (k .eq. 0) then
               write (iout,20)  i,name(i),atomic(i)
   20          format (/,' Atom:',i8,9x,'Name:',3x,a3,7x,
     &                    'Atomic Number:',i8)
               write (iout,30)
   30          format (/,' No Atomic Multipole Moments for this Site')
            else
               zaxe = zaxis(k)
               xaxe = xaxis(k)
               yaxe = yaxis(k)
               if (yaxe .lt. 0)  yaxe = -yaxe
               write (iout,40)  i,name(i),atomic(i)
   40          format (/,' Atom:',i8,9x,'Name:',3x,a3,
     &                    7x,'Atomic Number:',i8)
               write (iout,50)  polaxe(k),zaxe,xaxe,yaxe
   50          format (/,' Local Frame:',12x,a8,6x,3i8)
               write (iout,60)  rpole(1,k)
   60          format (/,' Charge:',10x,f15.5)
               write (iout,70)  rpole(2,k),rpole(3,k),rpole(4,k)
   70          format (' Dipole:',10x,3f15.5)
               write (iout,80)  rpole(5,k)
   80          format (' Quadrupole:',6x,f15.5)
               write (iout,90)  rpole(8,k),rpole(9,k)
   90          format (18x,2f15.5)
               write (iout,100)  rpole(11,k),rpole(12,k),rpole(13,k)
  100          format (18x,3f15.5)
            end if
         end do
      end if
      return
      end
c
c
c     #################################################################
c     ##                                                             ##
c     ##  subroutine fixframe  --  alter the local frame definition  ##
c     ##                                                             ##
c     #################################################################
c
c
c     "fixframe" is a service routine that alters the local frame
c     definition for specified atoms
c
c
      subroutine fixframe
      use atomid
      use atoms
      use couple
      use files
      use keys
      use kpolr
      use iounit
      use mpole
      use polar
      use units
      implicit none
      integer i,j,k
      integer ia,ib,ic
      integer xaxe
      integer yaxe
      integer zaxe
      real*8 eps,ci,cj
      real*8 big,sum
      logical query,change
      character*240 record
c
c
c     rotate the multipole components into the global frame
c
      call rotpole
c
c     list the local frame definition for each multipole site
c
      write (iout,10)
   10 format (/,' Local Frame Definition for Multipole Sites :')
      write (iout,20)
   20 format (/,5x,'Atom',5x,'Name',6x,'Axis Type',5x,'Z Axis',2x,
     &          'X Axis',2x,'Y Axis',/)
      do i = 1, n
         k = pollist(i)
         if (k .eq. 0) then
            write (iout,30)  i,name(i)
   30       format (i8,6x,a3,10x,'--',11x,'--',6x,'--',6x,'--')
         else
            zaxe = zaxis(k)
            xaxe = xaxis(k)
            yaxe = yaxis(k)
            if (yaxe .lt. 0)  yaxe = -yaxe
            write (iout,40)  i,name(i),polaxe(k),zaxe,xaxe,yaxe
   40       format (i8,6x,a3,7x,a8,2x,3i8)
         end if
      end do
c
c     allow the user to manually alter local coordinate frames
c
      query = .true.
      change = .false.
      do while (query)
         i = 0
         k = 0
         ia = 0
         ib = 0
         ic = 0
         write (iout,50)
   50    format (/,' Enter Altered Local Frame Definition',
     &              ' [<Enter>=Exit] :  ',$)
         read (input,60)  record
   60    format (a240)
         read (record,*,err=70,end=70)  k,ia,ib,ic
   70    continue
         if (k .eq. 0) then
            query = .false.
         else
            i = pollist(k)
         end if
         if (i .ne. 0) then
            change = .true.
            if (ia .eq. 0)  polaxe(i) = 'None'
            if (ia.ne.0 .and. ib.eq.0)  polaxe(i) = 'Z-Only'
            if (ia.gt.0 .and. ib.gt.0)  polaxe(i) = 'Z-then-X'
            if (ia.lt.0  .or. ib.lt.0)  polaxe(i) = 'Bisector'
            if (ib.lt.0 .and. ic.lt.0)  polaxe(i) = 'Z-Bisect'
            if (max(ia,ib,ic)  .lt. 0)  polaxe(i) = '3-Fold'
            zaxis(i) = abs(ia)
            xaxis(i) = abs(ib)
            yaxis(i) = abs(ic)
         end if
      end do
c
c     repeat local frame list if definitions were altered
c
      if (change) then
         write (iout,80)
   80    format (/,' Local Frame Definition for Multipole Sites :')
         write (iout,90)
   90    format (/,5x,'Atom',5x,'Name',6x,'Axis Type',5x,'Z Axis',2x,
     &             'X Axis',2x,'Y Axis',/)
         do k = 1, npole
            i = pollist(k)
            if (i .eq. 0) then
               write (iout,100)  k,name(k)
  100          format (i8,6x,a3,10x,'--',11x,'--',6x,'--',6x,'--')
            else
               zaxe = zaxis(i)
               xaxe = xaxis(i)
               yaxe = yaxis(i)
               if (yaxe .lt. 0)  yaxe = -yaxe
               write (iout,110)  k,name(k),polaxe(i),zaxe,xaxe,yaxe
  110          format (i8,6x,a3,7x,a8,2x,3i8)
            end if
         end do
      end if
c
c     rotate the multipoles from global frame to local frame
c
      call rotrpole
c
c     check the sign of multipole components at chiral sites
c
      call chkpole
c
c     convert dipole and quadrupole moments back to atomic units
c
      do i = 1, npole
         pole(1,i) = pole(1,i)
         do j = 2, 4
            pole(j,i) = pole(j,i) / bohr
         end do
         do j = 5, 13
            pole(j,i) = 3.0d0 * pole(j,i) / bohr**2
         end do
      end do
c
c     regularize the multipole moments to desired precision
c
      eps = 0.00001d0
      do i = 1, npole
         do j = 1, 13
            pole(j,i) = dble(nint(pole(j,i)/eps)) * eps
         end do
      end do
c
c     maintain integer net charge over atomic multipoles
c
      k = 0
      big = 0.0d0
      sum = 0.0d0
      do i = 1, npole
         sum = sum + pole(1,i)
         ci = abs(pole(1,i))
         if (ci .gt. big) then
            do j = 1, npole
               cj = abs(pole(1,j))
               if (i.ne.j .and. ci.eq.cj)  goto 120
            end do
            k = i
            big = ci
  120       continue
         end if
      end do
      sum = sum - dble(nint(sum))
      if (k .ne. 0)  pole(1,k) = pole(1,k) - sum
c
c     maintain traceless quadrupole at each multipole site
c
      do i = 1, npole
         sum = pole(5,i) + pole(9,i) + pole(13,i)
         big = max(abs(pole(5,i)),abs(pole(9,i)),abs(pole(13,i)))
         k = 0
         if (big .eq. abs(pole(5,i)))  k = 5
         if (big .eq. abs(pole(9,i)))  k = 9
         if (big .eq. abs(pole(13,i)))  k = 13
         if (pole(9,i) .eq. pole(13,i))  k = 5
         if (pole(5,i) .eq. pole(13,i))  k = 9
         if (pole(5,i) .eq. pole(9,i))  k = 13
         if (k .ne. 0)  pole(k,i) = pole(k,i) - sum
      end do
c
c     print the altered local frame atomic multipole values
c
      write (iout,130)
  130 format (/,' Multipoles With Altered Local Frame Definition :')
      do i = 1, n
         k = pollist(i)
         if (i .eq. 0) then
            write (iout,140)  i,name(i),atomic(i)
  140       format (/,' Atom:',i8,9x,'Name:',3x,a3,7x,
     &                 'Atomic Number:',i8)
            write (iout,150)
  150       format (/,' No Atomic Multipole Moments for this Site')
         else
            zaxe = zaxis(k)
            xaxe = xaxis(k)
            yaxe = yaxis(k)
            if (yaxe .lt. 0)  yaxe = -yaxe
            write (iout,160)  i,name(i),atomic(i)
  160       format (/,' Atom:',i8,9x,'Name:',3x,a3,
     &                 7x,'Atomic Number:',i8)
            write (iout,170)  polaxe(k),zaxe,xaxe,yaxe
  170       format (/,' Local Frame:',12x,a8,6x,3i8)
            write (iout,180)  pole(1,k)
  180       format (/,' Charge:',10x,f15.5)
            write (iout,190)  pole(2,k),pole(3,k),pole(4,k)
  190       format (' Dipole:',10x,3f15.5)
            write (iout,200)  pole(5,k)
  200       format (' Quadrupole:',6x,f15.5)
            write (iout,210)  pole(8,k),pole(9,k)
  210       format (18x,2f15.5)
            write (iout,220)  pole(11,k),pole(12,k),pole(13,k)
  220       format (18x,3f15.5)
         end if
      end do
      return
      end
c
c
c     ##############################################################
c     ##                                                          ##
c     ##  subroutine setpolar  --  define the polarization model  ##
c     ##                                                          ##
c     ##############################################################
c
c
c     "setpolar" assigns atomic polarizabilities, Thole damping, 
c     direct damping or charge penetration parameters, and allows 
c     user modification
c
c     note this routine contains directly coded scale factors, and
c     Thole, dirdamp and charge penetration values for atom types i
c     that should be updated if the default force field values are modified
c
c
      subroutine setpolar
      use atomid
      use atoms
      use chgpen
      use couple
      use fields
      use iounit
      use mplpot
      use mpole
      use polar
      use polpot
      implicit none
      integer i,j,k,m,jj
      integer atn,next
      real*8 pol,thl,ddp
      real*8 pel,pal
      real*8 sixth
      logical exist,query
      logical change
      logical aromatic
      logical chkarom
      character*1 answer
      character*240 record
      character*240 string
      external chkarom
c
c
c     allow the user to select the polarization model
c
      forcefield = 'AMOEBA'
      use_thole = .true.
      use_dirdamp = .false.
      use_chgpen = .false.
      dpequal = .false.
      query = .true.
      answer = ' '
      call nextarg (string,exist)
      if (exist) then
         read (string,*,err=10,end=10)  answer
         call upcase (answer)
         if (answer.eq.'A' .or. answer .eq. 'P' .or. answer.eq.'H') 
     &      query = .false.
      end if
   10 continue
      if (query) then
         answer = 'A'
         write (iout,20)
   20    format (/,' Choose Either the AMOEBA, AMOEBA+ or HIPPO', 
     &             ' Polarization Model [A] : ', $)
         read (input,30)  record
   30    format (a240)
         next = 1
         call gettext (record,answer,next)
         call upcase (answer)
      end if
      if (answer .eq. 'P') then
         forcefield = 'APLUS'
         use_dirdamp = .true.
         use_thole = .false.
         dpequal = .true.
      else if (answer .eq. 'H') then
         forcefield = 'HIPPO'
         use_thole = .false.
         use_chgpen = .true.
         dpequal = .true.
      end if
c
c     perform dynamic allocation of some global arrays
c
      if (.not. allocated(polarity))  allocate (polarity(n))
      if (.not. allocated(thole))  allocate (thole(n))
      if (.not. allocated(dirdamp))  allocate (dirdamp(n))
      if (.not. allocated(pdamp))  allocate (pdamp(n))
      if (.not. allocated(pcore))  allocate (pcore(n))
      if (.not. allocated(pval))  allocate (pval(n))
      if (.not. allocated(palpha))  allocate (palpha(n))
c
c     zero out the polarization and charge penetration values
c
      do i = 1, n
         polarity(i) = 0.0d0
         thole(i) = 0.0d0
         dirdamp(i) = 0.0d0
         pdamp(i) = 0.0d0
         pcore(i) = 0.0d0
         pval(i) = 0.0d0
         palpha(i) = 0.0d0
      end do
c
c     set multipole and polarization scale factors for AMOEBA
c
      if (forcefield .eq. 'AMOEBA') then
         m2scale = 0.0d0
         m3scale = 0.0d0
         m4scale = 0.4d0
         m5scale = 0.8d0
         p2scale = 0.0d0
         p3scale = 0.0d0
         p4scale = 1.0d0
         p5scale = 1.0d0
         p2iscale = 0.0d0
         p3iscale = 0.0d0
         p4iscale = 0.5d0
         p5iscale = 1.0d0
         d1scale = 0.0d0
         d2scale = 1.0d0
         d3scale = 1.0d0
         d4scale = 1.0d0
         u1scale = 1.0d0
         u2scale = 1.0d0
         u3scale = 1.0d0
         u4scale = 1.0d0
      end if
c
c     set multipole and polarization scale factors for HIPPO
c
      if (forcefield .eq. 'HIPPO') then
         m2scale = 0.0d0
         m3scale = 0.0d0
         m4scale = 0.4d0
         m5scale = 0.8d0
         p2scale = 0.0d0
         p3scale = 0.5d0
         p4scale = 1.0d0
         p5scale = 1.0d0
         p2iscale = 0.0d0
         p3iscale = 0.0d0
         p4iscale = 0.0d0
         p5iscale = 0.5d0
         d1scale = 0.0d0
         d2scale = 1.0d0
         d3scale = 1.0d0
         d4scale = 1.0d0
         u1scale = 1.0d0
         u2scale = 1.0d0
         u3scale = 1.0d0
         u4scale = 1.0d0
         w2scale = 0.2d0
         w3scale = 1.0d0
         w4scale = 1.0d0
         w5scale = 1.0d0
      end if
c
c     set multipole and polarization scale factors for AMOEBAPLUS 
c
      if (forcefield .eq. 'APLUS') then
         m2scale = 0.0d0
         m3scale = 0.0d0
         m4scale = 0.5d0
         m5scale = 1.0d0
         p2scale = 0.0d0
         p3scale = 0.0d0
         p4scale = 0.5d0
         p5scale = 0.5d0
         p2iscale = 0.0d0
         p3iscale = 0.0d0
         p4iscale = 0.0d0
         p5iscale = 0.0d0
         d1scale = 0.0d0
         d2scale = 1.0d0
         d3scale = 1.0d0
         d4scale = 1.0d0
         u1scale = 1.0d0
         u2scale = 1.0d0
         u3scale = 1.0d0
         u4scale = 1.0d0
         do i = 1, n
            thole(i) = 0.39d0
            dirdamp(i) = 0.70d0 
         end do
      end if
c
c     assign default atomic polarizabilities for AMOEBA model
c
      if (forcefield .eq. 'AMOEBA') then
         do i = 1, n
            thole(i) = 0.39d0
            atn = atomic(i)
            if (atn .eq. 1) then
               polarity(i) = 0.496d0
            else if (atn .eq. 5) then
               polarity(i) = 1.600d0
            else if (atn .eq. 6) then
               polarity(i) = 1.334d0
            else if (atn .eq. 7) then
               polarity(i) = 1.073d0
            else if (atn .eq. 8) then
               polarity(i) = 0.837d0
            else if (atn .eq. 9) then
               polarity(i) = 0.507d0
            else if (atn .eq. 14) then
               polarity(i) = 3.640d0
            else if (atn .eq. 15) then
               polarity(i) = 1.828d0
            else if (atn .eq. 16) then
               polarity(i) = 3.300d0
            else if (atn .eq. 17) then
               polarity(i) = 2.500d0
            else if (atn .eq. 35) then
               polarity(i) = 3.595d0
            else if (atn .eq. 53) then
               polarity(i) = 5.705d0
            end if
         end do
c
c     alter polarizabilities for alkene/aromatic carbon and hydrogen
c
         do i = 1, n
            atn = atomic(i)
            if (atn .eq. 1) then
               j = i12(1,i)
               if (atomic(j).eq.6 .and. n12(j).eq.3) then
                  polarity(i) = 0.696d0
                  do k = 1, n12(j)
                     m = i12(k,j)
                     if (atomic(m).eq.8 .and. n12(m).eq.1) then
                        polarity(i) = 0.494d0
                     end if
                  end do
               end if
            else if (atn .eq. 6) then
               if (n12(i) .eq. 3) then
                  polarity(i) = 1.75d0
                  do j = 1, n12(i)
                     k = i12(j,i)
                     if (atomic(k).eq.8 .and. n12(k).eq.1) then
                        polarity(i) = 1.334d0
                     end if
                  end do
               end if
            end if
         end do
      end if
c
c     assign default atom-based parameters for HIPPO model
c
      if (forcefield .eq. 'HIPPO') then
         do i = 1, n
            atn = atomic(i)
            if (atn .eq. 1) then
               pcore(i) = 1.0d0
               polarity(i) = 0.373d0
               palpha(i) = 4.3225d0
               k = atomic(i12(1,i))
               if (k .eq. 6) then
                  do j = 1, n13(i)
                     m = atomic(i13(j,i))
                     if ((atomic(m).ne.6.or.n12(m).ne.4)
     &                     .and. atomic(m).ne.1)  goto 40
                  end do
                  do j = 1, n14(i)
                     m = i14(j,i)
                     if ((atomic(m).ne.6.or.n12(m).ne.4)
     &                     .and. atomic(m).ne.1)  goto 40
                  end do
                  polarity(i) = 0.504d0
                  palpha(i) = 4.9530d0
   40             continue
                  aromatic = chkarom (k)
                  if (aromatic) then
                     polarity(i) = 0.1106d0
                     palpha(i) = 4.9530d0
                  end if
               else if (k .eq. 7) then
                  polarity(i) = 0.005d0
                  palpha(i) = 5.5155d0
               else if (k .eq. 8) then
                  polarity(i) = 0.3698d0
                  palpha(i) = 4.7441d0
               else if (k .eq. 16) then
                  polarity(i) = 0.2093d0
                  palpha(i) = 4.3952d0
               end if
            else if (atn .eq. 5) then
               pcore(i) = 3.0d0
               polarity(i) = 1.6d0
               palpha(i) = 0.0d0      !! missing parameter
            else if (atn .eq. 6) then
               pcore(i) = 4.0d0
               polarity(i) = 0.9354d0
               palpha(i) = 4.5439d0
               do j = 1, n12(i)
                  k = i12(j,i)
                  if ((atomic(k).ne.6.or.n12(k).ne.4)
     &                  .and. atomic(k).ne.1)  goto 50
               end do
               do j = 1, n13(i)
                  k = atomic(i13(j,i))
                  if ((atomic(k).ne.6.or.n12(k).ne.4)
     &                  .and. atomic(k).ne.1)  goto 50
               end do
               polarity(i) = 0.755d0
               palpha(i) = 4.2998d0
   50          continue
               if (n12(i) .eq. 3) then
                  do j = 1, n12(i)
                     k = i12(j,i)
                     if (atomic(k).eq.6 .and. n12(k).eq.3) then
                        polarity(i) = 1.9384d0
                        palpha(i) = 3.5491d0
                     end if
                  end do
                  do j = 1, n12(i)
                     k = i12(j,i)
                     if (atomic(k).eq.8 .and. n12(k).eq.1) then
                        polarity(i) = 0.6577d0
                        palpha(i) = 5.9682d0
                     end if
                  end do
               end if
               if (chkarom(i)) then
                  polarity(i) = 1.5624d0
                  palpha(i) = 3.8056d0
                  do j = 1, n12(i)
                     k = atomic(i12(j,i))
                     if (k.ne.6 .and. k.ne.1) then
                        polarity(i) = 1.2811d0
                        palpha(i) = 3.8066d0
                     end if
                  end do
               end if
               if (n12(i) .eq. 2) then
                  polarity(i) = 0.9354d0    !! generic value
                  palpha(i) = 4.5439d0      !! generic value
               end if
            else if (atn .eq. 7) then
               pcore(i) = 5.0d0
               polarity(i) = 1.4289d0
               palpha(i) = 3.9882d0
               if (n12(i) .eq. 3) then
                  do j = 1, n12(i)
                     k = i12(j,i)
                     if (atomic(k).eq.6 .and. n12(k).eq.3) then
                        polarity(i) = 1.4545d0
                        palpha(i) = 3.9413d0
                     end if
                  end do
               end if
               if (chkarom(i)) then
                  polarity(i) = 1.3037d0
                  palpha(i) = 3.9434d0
               end if
            else if (atn .eq. 8) then
               pcore(i) = 6.0d0
               polarity(i) = 0.6645d0
               palpha(i) = 4.7004d0
               if (n12(i) .eq. 1) then
                  k = i12(1,i)
                  if (atomic(k).eq.6 .and. n12(k).eq.3) then
                     polarity(i) = 1.4266d0
                     palpha(i) = 4.2263d0
                     do j = 1, n13(i)
                        m = i13(j,i)
                        if (atomic(m).eq.8 .and. n12(m).eq.1) then
                           polarity(i) = 1.8809d0
                           palpha(i) = 4.0355d0
                        end if
                     end do
                  end if
                  if (atomic(k) .eq. 15) then
                     jj = 0
                     do j = 1, n12(k)
                        m = i12(j,k)
                        if (atomic(m).eq.8 .and. n12(m).eq.1) then
                           jj = jj + 1
                        end if
                     end do
                     if (jj .eq. 1) then
                        polarity(i) = 1.0d0
                        palpha(i) = 4.3312d0
                     else
                        polarity(i) = 1.0d0
                        palpha(i) = 4.4574d0
                     end if
                  end if
               end if
            else if (atn .eq. 9) then
               pcore(i) = 7.0d0
               polarity(i) = 0.5d0
               palpha(i) = 5.5080d0
            else if (atn .eq. 15) then
               pcore(i) = 5.0d0
               polarity(i) = 1.8d0
               palpha(i) = 2.8130d0
            else if (atn .eq. 16) then
               pcore(i) = 6.0d0
               polarity(i) = 3.1967d0
               palpha(i) = 3.3620d0
               if (n12(i) .gt. 2) then
                  polarity(i) = 2.458d0
                  palpha(i) = 2.7272d0
               end if
            else if (atn .eq. 17) then
               pcore(i) = 7.0d0
               polarity(i) = 2.366d0
               palpha(i) = 3.6316d0
            else if (atn .eq. 35) then
               pcore(i) = 7.0d0
               polarity(i) = 3.4458d0
               palpha(i) = 3.2008d0
            else if (atn .eq. 53) then
               pcore(i) = 7.0d0
               polarity(i) = 5.5d0
               palpha(i) = 0.0d0      !! missing parameter
            end if
         end do
      end if
c
c     set valence electrons from number of core electrons
c
      do i = 1, n
         pval(i) = pole(1,i) - pcore(i)
      end do
c
c     compute the Thole polarizability damping values
c
      sixth = 1.0d0 / 6.0d0
      do i = 1, n
         if (thole(i) .eq. 0.0d0) then
            pdamp(i) = 0.0d0
         else
            pdamp(i) = polarity(i)**sixth
         end if
      end do
c
c     list the polarizability and charge penetration values
c
      write (iout,60)
   60 format (/,' Polarizability Parameters for Multipole Sites :')
      if (use_thole) then
         write (iout,70)
   70    format (/,5x,'Atom',5x,'Name',7x,'Polarize',10x,'Thole',/)
      else if (use_dirdamp) then
         write (iout,75)
   75    format (/,5x,'Atom',5x,'Name',7x,'Polarize',11x,'Thole',
     &             8x,'DirDamp',/)
      else if (use_chgpen) then
         write (iout,80)
   80    format (/,5x,'Atom',5x,'Name',7x,'Polarize',11x,'Core',
     &              5x,'Valence',8x,'Damp',/)
      end if
      do k = 1, n
         i = pollist(k)
         if (use_thole) then
            if (i .eq. 0) then
               write (iout,90)  k,name(k)
   90          format (i8,6x,a3,12x,'--',13x,'--')
            else
               write (iout,100)  k,name(k),polarity(i),thole(i)
  100          format (i8,6x,a3,4x,f12.4,3x,f12.4)
            end if
         else if (use_dirdamp) then
            if (i .eq. 0) then
               write (iout,105)  k,name(k)
  105          format (i8,6x,a3,12x,'--',13x,'--', 13x, '--')
            else
               write (iout,108) k,name(k),polarity(i),
     &                thole(i),dirdamp(i)
  108          format (i8,6x,a3,4x,f12.4,3x,f12.4,3x,f12.4)
            end if
         else if (use_chgpen) then
            if (i .eq. 0) then
               write (iout,110)  k,name(k)
  110          format (i8,6x,a3,12x,'--',13x,'--',10x,'--',10x,'--')
            else
               write (iout,120)  k,name(k),polarity(i),pcore(i),
     &                           pval(i),palpha(i)
  120          format (i8,6x,a3,4x,f12.4,3x,3f12.4)
            end if
         end if
      end do
c
c     allow the user to manually alter polarizability values
c
      change = .false.
      query = .true.
      i = -1
      call nextarg (string,exist)
      if (exist) then
         read (string,*,err=130,end=130)  i
         if (i .eq. 0)  query = .false.
      end if
  130 continue
      do while (query)
         i = 0
         k = 0
         if (use_thole) then
            pol = 0.0d0
            thl = 0.39d0
            write (iout,140)
  140       format (/,' Enter Atom Number, Polarizability & Thole',
     &                 ' Values :  ',$)
            read (input,150)  record
  150       format (a240)
            read (record,*,err=160,end=160)  k,pol,thl
  160       continue
            if (k .ne. 0) then
               i = pollist(k)
               if (pol .eq. 0.0d0)  pol = polarity(i)
               if (thl .eq. 0.0d0)  thl = thole(i)
            end if
         else if (use_dirdamp) then
            pol = 0.0d0
            thl = 0.39d0
            ddp = 0.70d0
            write (iout,162)
  162       format (/,' Enter Atom Number, Polarizability, Thole &' 
     &                 ' DirDamp Values :  ',$)
            read (input,165)  record
  165       format (a240)
            read (record,*,err=168,end=168)  k,pol,thl,ddp
  168       continue
            if (k .ne. 0) then
               i = pollist(k)
               if (pol .eq. 0.0d0)  pol = polarity(i)
               if (thl .eq. 0.0d0)  thl = thole(i)
               if (ddp .eq. 0.0d0)  ddp = dirdamp(i)
            end if
         else if (use_chgpen) then
            pol = 0.0d0
            pel = 0.0d0
            pal = 0.0d0
            write (iout,170)
  170       format (/,' Enter Atom Number, Polarize, Core & Damp',
     &                 ' Values :  ',$)
            read (input,180)  record
  180       format (a240)
            read (record,*,err=190,end=190)  k,pol,pel,pal
  190       continue
            if (k .ne. 0) then
               i = pollist(k)
               if (pol .eq. 0.0d0)  pol = polarity(i)
               if (pel .eq. 0.0d0)  pel = pcore(i)
               if (pal .eq. 0.0d0)  pal = palpha(i)
            end if
         end if
         if (k .eq. 0) then
            query = .false.
         else
            i = pollist(k)
         end if
         if (i .ne. 0) then
            change = .true.
            polarity(i) = pol
            if (use_thole) then
               thole(i) = thl
               pdamp(i) = polarity(i)**sixth
            else if (use_dirdamp) then
               thole(i) = thl
               dirdamp(i) = ddp
               pdamp(i) = polarity(i)**sixth
            else if (use_chgpen) then
               pcore(i) = pel
               palpha(i) = pal
               pval(i) = pole(1,i) - pcore(i)
            end if
         end if
      end do
c
c     repeat polarizability values if parameters were altered
c
      if (change) then
         write (iout,200)
  200    format (/,' Atomic Polarizabilities for Multipole Sites :')
         if (use_thole) then
            write (iout,210)
  210       format (/,5x,'Atom',5x,'Name',7x,'Polarize',10x,'Thole',/)
         else if (use_dirdamp) then
            write (iout,215)
  215       format (/,5x,'Atom',5x,'Name',7x,'Polarize',10x,'Thole', 
     &                10x, 'DirDamp',/)
         else if (use_chgpen) then
            write (iout,220)
  220       format (/,5x,'Atom',5x,'Name',7x,'Polarize',4x,'Core Chg',
     &                 8x,'Damp',/)
         end if
         do k = 1, n
            i = pollist(k)
            if (use_thole) then
               if (i .eq. 0) then
                  write (iout,230)  k,name(k)
  230             format (i8,6x,a3,12x,'--',13x,'--')
               else
                  write (iout,240)  k,name(k),polarity(i),thole(i)
  240             format (i8,6x,a3,4x,f12.4,3x,f12.4)
               end if
            else if (use_dirdamp) then
               if (i .eq. 0) then
                  write (iout,245)  k,name(k)
  245             format (i8,6x,a3,12x,'--',13x,'--',13x, '--')
               else
                  write (iout,248)  k,name(k),polarity(i),
     &                   thole(i), dirdamp(i)
  248             format (i8,6x,a3,4x,f12.4,3x,f12.4,f12.4)
               end if
            else if (use_chgpen) then
               if (i .eq. 0) then
                  write (iout,250)  k,name(k)
  250             format (i8,6x,a3,12x,'--',13x,'--',10x,'--')
               else
                  write (iout,260)  k,name(k),polarity(i),pcore(i),
     &                              palpha(i)
  260             format (i8,6x,a3,4x,f12.4,3x,2f12.4)
               end if
            end if
         end do
      end if
      return
      end
c
c
c     ##############################################################
c     ##                                                          ##
c     ##  subroutine setpgrp  --  define the polarization groups  ##
c     ##                                                          ##
c     ##############################################################
c
c
c     "setpgrp" chooses the polarization groups as defined by bonds
c     separating groups, and allows user modification of the groups
c
c
      subroutine setpgrp
      use atomid
      use atoms
      use bndstr
      use couple
      use iounit
      use kpolr
      use ring
      implicit none
      integer i,j,k,m
      integer mode
      integer ia,ib,ic
      integer ita,itb,itc
      integer ata,atb
      integer n12a,n12b
      logical exist,query
      logical chkarom,split
      logical aroma,aromb
      character*240 record
      character*240 string
c
c
c     get the desired type of coordinate file modification
c
      mode = -1
      query = .true.
      call nextarg (string,exist)
      if (exist) then
         read (string,*,err=10,end=10)  mode
         if (mode.ge.1 .and. mode.le.2)  query = .false.
      end if
   10 continue
      if (query) then
         write (iout,20)
   20    format (/,' Choose Method for Division into Polarization',
     &              ' Groups :',
     &           //,4x,'(1) Put All Atoms in One Polarization Group',
     &           /,4x,'(2) Separate into Groups at Rotatable Bonds',
     &           /,4x,'(3) Manual Entry of Bonds Separating Groups')
         do while (mode.lt.1 .or. mode.gt.3)
            mode = 0
            write (iout,30)
   30       format (/,' Enter the Number of the Desired Choice',
     &                 ' [1] :  ',$)
            read (input,40,err=50,end=50)  mode
   40       format (i10)
            if (mode .le. 0)  mode = 1
   50       continue
         end do
      end if
c
c     initialize by placing all atoms in one polarization group
c
      do i = 1, n
         do j = 1, n12(i)
            pgrp(j,i) = i12(j,i)
         end do
      end do
c
c     separate into polarization groups at rotatable bonds
c
      if (mode .eq. 2) then
         call bonds
         do k = 1, nbond
            ia = ibnd(1,k)
            ib = ibnd(2,k)
            n12a = n12(ia)
            n12b = n12(ib)
            ata = atomic(ia)
            atb = atomic(ib)
            ita = 10*ata + n12a
            itb = 10*atb + n12b
            aroma = chkarom(ia)
            aromb = chkarom(ib)
            split = .true.
c
c     remove bonds involving univalent atoms
c
            if (min(n12a,n12b) .le. 1)  split = .false.
c
c     remove bonds internal to aromatic ring
c
            if (aroma .and. aromb) then
               do i = 1, nring5
                  m = 0
                  do j = 1, 5
                     if (iring5(j,i) .eq. ia)  m = m + 1
                     if (iring5(j,i) .eq. ib)  m = m + 1
                  end do
                  if (m .eq. 2)  split = .false.
               end do
               do i = 1, nring6
                  m = 0
                  do j = 1, 6
                     if (iring6(j,i) .eq. ia)  m = m + 1
                     if (iring6(j,i) .eq. ib)  m = m + 1
                  end do
                  if (m .eq. 2)  split = .false.
               end do
            end if
c
c     remove bonds with sp-hybridized carbon atom
c
            if (ita.eq.62 .or. itb.eq.62)  split = .false.
c
c     remove the C=C bond of terminal alkene
c
            if (ita.eq.63 .and. .not.aroma .and.
     &             itb.eq.63 .and. .not.aromb) then
               split = .false.
               do i = 1, n12a
                  ic = i12(i,ia)
                  if (ic .ne. ib) then
                     itc = 10*atomic(ic) + n12(ic)
                     if (itc.eq.63 .or. itc.eq.73 .or.
     &                   itc.eq.72 .or. itc.eq.81) then
                        split = .true.
                     end if
                  end if
               end do
               if (split) then
                  split = .false.
                  do i = 1, n12b
                     ic = i12(i,ib)
                     if (ic .ne. ia) then
                        itc = 10*atomic(ic) + n12(ic)
                        if (itc.eq.63 .or. itc.eq.72 .or.
     &                      itc.eq.73 .or. itc.eq.81) then
                           split = .true.
                        end if
                     end if
                  end do
               end if
            end if
c
c     remove the C-O bonds of alcohol and ether
c
            if (ita.eq.82 .and. itb.eq.64) then
               do i = 1, n12a
                  ic = i12(i,ia)
                  if (ic .ne. ib) then
                     itc = 10*atomic(ic) + n12(ic)
                     if (itc.eq.11 .or. itc.eq.64)  split = .false.
                  end if
               end do
            else if (itb.eq.82 .and. ita.eq.64) then
               do i = 1, n12b
                  ic = i12(i,ib)
                  if (ic .ne. ia) then
                     itc = 10*atomic(ic) + n12(ic)
                     if (itc.eq.11 .or. itc.eq.64)  split = .false.
                  end if
               end do
            end if
c
c     remove the C-O bonds of carboxylic acid and ester
c
            if (ita.eq.82 .and. itb.eq.63) then
               do i = 1, n12b
                  ic = i12(i,ib)
                  itc = 10*atomic(ic) + n12(ic)
                  if (itc .eq. 81)  split = .false.
               end do
            else if (itb.eq.82 .and. ita.eq.63) then
               do i = 1, n12a
                  ic = i12(i,ia)
                  itc = 10*atomic(ic) + n12(ic)
                  if (itc .eq. 81)  split = .false.
               end do
            end if
c
c     remove the C-N bonds of alkyl amine
c
            if (ita.eq.73 .and. itb.eq.64) then
               m = 0
               do i = 1, n12a
                  ic = i12(i,ia)
                  if (ic .ne. ib) then
                     itc = 10*atomic(ic) + n12(ic)
                     if (itc.eq.11 .or. itc.eq.64)  m = m + 1
                  end if
               end do
               if (m .eq. 2)  split = .false.
            else if (itb.eq.73 .and. ita.eq.64) then
               m = 0
               do i = 1, n12b
                  ic = i12(i,ib)
                  if (ic .ne. ia) then
                     itc = 10*atomic(ic) + n12(ic)
                     if (itc.eq.11 .or. itc.eq.64)  m = m + 1
                  end if
               end do
               if (m .eq. 2)  split = .false.
            end if
c
c     remove the C-N bonds of amide, urea, amidine and guanidinium
c
            if (ita.eq.73 .and. itb.eq.63) then
               do i = 1, n12b
                  ic = i12(i,ib)
                  if (ic .ne. ia) then
                     itc = 10*atomic(ic) + n12(ic)
                     if (itc .eq. 81)  split = .false.
                     if (itc .eq. 73)  split = .false.
                  end if
               end do
            else if (itb.eq.73 .and. ita.eq.63) then
               do i = 1, n12a
                  ic = i12(i,ia)
                  if (ic .ne. ib) then
                     itc = 10*atomic(ic) + n12(ic)
                     if (itc .eq. 81)  split = .false.
                     if (itc .eq. 73)  split = .false.
                  end if
               end do
            end if
c
c     remove any P-X and S-X bonds with X = N or O
c
            if (ata.eq.15 .or. ata.eq.16) then
               if (atb.eq.7 .or. atb.eq.8)  split = .false.
            else if (atb.eq.15 .or. atb.eq.16) then
               if (ata.eq.7 .or. ata.eq.8)  split = .false.
            end if
c
c     modify membership to split groups at allowed bonds
c
            if (split) then
               do i = 1, n12a
                  if (pgrp(i,ia) .eq. ib) then
                     do j = i+1, n12a
                        pgrp(j-1,ia) = pgrp(j,ia)
                     end do
                     pgrp(n12a,ia) = 0
                  end if
               end do
               do i = 1, n12b
                  if (pgrp(i,ib) .eq. ia) then
                     do j = i+1, n12b
                        pgrp(j-1,ib) = pgrp(j,ib)
                     end do
                     pgrp(n12b,ib) = 0
                  end if
               end do
            end if
         end do
c
c     allow modification of polarization group one bond at a time
c
      else if (mode .eq. 3) then
         write (iout,60)
   60    format (/,' All atoms are placed initially into one',
     &              ' polarization group;',
     &           /,' This can be modified by entering a series',
     &              ' of bonded atom pairs',
     &           /,' that separate the molecule into distinct',
     &              ' polarization groups')
c
c     get the bonds that separate the polarization groups
c
         query = .true.
         i = -1
         call nextarg (string,exist)
         if (exist) then
            read (string,*,err=70,end=70)  i
            if (i .eq. 0)  query = .false.
         end if
   70    continue
         do while (query)
            ia = 0
            ib = 0
            write (iout,80)
   80       format (/,' Enter a Bond between Polarization Groups',
     &                 ' [<Enter>=Exit] :  ',$)
            read (input,90)  record
   90       format (a240)
            read (record,*,err=100,end=100)  ia,ib
  100       continue
            if (ia.eq.0 .or. ib.eq.0) then
               query = .false.
            else
               do i = 1, n12(ia)
                  if (pgrp(i,ia) .eq. ib) then
                     do j = i+1, n12(ia)
                        pgrp(j-1,ia) = pgrp(j,ia)
                     end do
                     pgrp(n12(ia),ia) = 0
                  end if
               end do
               do i = 1, n12(ib)
                  if (pgrp(i,ib) .eq. ia) then
                     do j = i+1, n12(ib)
                        pgrp(j-1,ib) = pgrp(j,ib)
                     end do
                     pgrp(n12(ib),ib) = 0
                  end if
               end do
            end if
         end do
      end if
c
c     find the polarization groups and their connectivities
c
      call polargrp
c
c     list the polarization group for each multipole site
c
      write (iout,110)
  110 format (/,' Polarization Groups for Multipole Sites :')
      write (iout,120)
  120 format (/,5x,'Atom',5x,'Name',7x,'Polarization Group',
     &           ' Definition',/)
      do i = 1, n
         k = 0
         do j = 1, maxval
            if (pgrp(j,i) .ne. 0)  k = j
         end do
         write (iout,130)  i,name(i),(pgrp(j,i),j=1,k)
  130    format (i8,6x,a3,8x,20i6)
      end do
      return
      end
c
c
c     #############################################################
c     ##                                                         ##
c     ##  function chkarom  --  check for atom in aromatic ring  ##
c     ##                                                         ##
c     #############################################################
c
c
c     "chkatom" tests for the presence of a specified atom as a
c     member of an aromatic ring
c
c
      function chkarom (iatom)
      use atomid
      use couple
      use ring
      implicit none
      integer i,j,k
      integer iatom
      logical chkarom
      logical member
      logical trigonal
c
c
c     determine membership in 5-membered aromatic ring
c
      chkarom = .false.
      do i = 1, nring5
         trigonal = .true.
         member = .false.
         do j = 1, 5
            k = iring5(j,i)
            if (k .eq. iatom)  member = .true.
            if (atomic(k).eq.6 .and. n12(k).ne.3)  trigonal = .false.
            if (atomic(k).eq.7 .and. n12(k).eq.4)  trigonal = .false.
         end do
         if (member .and. trigonal)  chkarom = .true.
      end do
c
c     determine membership in 6-membered aromatic ring
c
      do i = 1, nring6
         trigonal = .true.
         member = .false.
         do j = 1, 6
            k = iring6(j,i)
            if (k .eq. iatom)  member = .true.
            if (atomic(k).eq.6 .and. n12(k).ne.3)  trigonal = .false.
            if (atomic(k).eq.7 .and. n12(k).eq.4)  trigonal = .false.
         end do
         if (member .and. trigonal)  chkarom = .true.
      end do
      return
      end
c
c
c     ##################################################################
c     ##                                                              ##
c     ##  subroutine alterpol  --  alter multipoles for polarization  ##
c     ##                                                              ##
c     ##################################################################
c
c
c     "alterpol" finds an output set of atomic multipole parameters
c     which when used with an intergroup polarization model will
c     give the same electrostatic potential around the molecule as
c     the input set of multipole parameters with all atoms in one
c     polarization group
c
c     for example, the input parameters could be from a distributed
c     multipole analysis of a molecular wavefunction and the output
c     will be the multipole moments that achieve the same potential
c     in the presence of intergroup (intramolecular) polarization
c
c
      subroutine alterpol
      use atomid
      use atoms
      use inform
      use iounit
      use mpole
      use polar
      use units
      implicit none
      integer i,j,k
      integer xaxe
      integer yaxe
      integer zaxe
c
c
c     compute induced dipoles to be removed from QM multipoles
c
      call interpol
c
c     remove intergroup induced dipoles from atomic multipoles
c
      do i = 1, npole
         pole(2,i) = pole(2,i) - uind(1,i)
         pole(3,i) = pole(3,i) - uind(2,i)
         pole(4,i) = pole(4,i) - uind(3,i)
      end do
c
c     convert dipole and quadrupole moments back to atomic units
c
      do i = 1, npole
         rpole(1,i) = pole(1,i)
         do j = 2, 4
            rpole(j,i) = pole(j,i) / bohr
         end do
         do j = 5, 13
            rpole(j,i) = 3.0d0 * pole(j,i) / bohr**2
         end do
      end do
c
c     print multipoles with intergroup polarization removed
c
      if (verbose) then
         write (iout,10)
   10    format (/,' Multipoles after Removal of Intergroup',
     &              ' Polarization :')
         do i = 1, n
            k = pollist(i)
            if (i .eq. 0) then
               write (iout,20)  i,name(i),atomic(i)
   20          format (/,' Atom:',i8,9x,'Name:',3x,a3,
     &                    7x,'Atomic Number:',i8)
               write (iout,30)
   30          format (/,' No Atomic Multipole Moments for this Site')
            else
               zaxe = zaxis(k)
               xaxe = xaxis(k)
               yaxe = yaxis(k)
               if (yaxe .lt. 0)  yaxe = -yaxe
               write (iout,40)  i,name(i),atomic(i)
   40          format (/,' Atom:',i8,9x,'Name:',3x,a3,
     &                    7x,'Atomic Number:',i8)
               write (iout,50)  polaxe(k),zaxe,xaxe,yaxe
   50          format (/,' Local Frame:',12x,a8,6x,3i8)
               write (iout,60)  rpole(1,k)
   60          format (/,' Charge:',10x,f15.5)
               write (iout,70)  rpole(2,k),rpole(3,k),rpole(4,k)
   70          format (' Dipole:',10x,3f15.5)
               write (iout,80)  rpole(5,k)
   80          format (' Quadrupole:',6x,f15.5)
               write (iout,90)  rpole(8,k),rpole(9,k)
   90          format (18x,2f15.5)
               write (iout,100)  rpole(11,k),rpole(12,k),rpole(13,k)
  100          format (18x,3f15.5)
            end if
         end do
      end if
      return
      end
c
c
c     ###############################################################
c     ##                                                           ##
c     ##  subroutine interpol  --  get intergroup induced dipoles  ##
c     ##                                                           ##
c     ###############################################################
c
c
c     "interpol" computes intergroup induced dipole moments for use
c     during removal of intergroup polarization
c
c     note only DIRECT and MUTUAL polarization models are available;
c     the analytical OPT and TCG methods are treated as MUTUAL
c
c
      subroutine interpol
      use atoms
      use iounit
      use mplpot
      use mpole
      use polar
      use polpot
      use units
      implicit none
      integer i,j,k,iter
      integer maxiter
      integer trimtext
      real*8 eps,epsold
      real*8 polmin,norm
      real*8 a,b,sum,term
      real*8 utmp(3)
      real*8 rmt(3,3)
      real*8, allocatable :: poli(:)
      real*8, allocatable :: field(:,:)
      real*8, allocatable :: rsd(:,:)
      real*8, allocatable :: zrsd(:,:)
      real*8, allocatable :: conj(:,:)
      real*8, allocatable :: vec(:,:)
      logical done
      logical planar
      character*5 truth
c
c
c     perform dynamic allocation of some global arrays
c
      if (.not. allocated(uind))  allocate (uind(3,npole))
c
c     perform dynamic allocation of some local arrays
c
      allocate (poli(npole))
      allocate (field(3,npole))
      allocate (rsd(3,npole))
      allocate (zrsd(3,npole))
      allocate (conj(3,npole))
      allocate (vec(3,npole))
c
c     rotate the multipole components into the global frame
c
      call rotpole
c
c     compute induced dipoles as polarizability times field
c
      call dfieldi (field)
      do i = 1, npole
         do j = 1, 3
            uind(j,i) = polarity(i) * field(j,i)
         end do
      end do
c
c     for direct-only models set mutual scale factors to zero
c
      if (poltyp .eq. 'DIRECT') then
         u1scale = 0.0d0
         u2scale = 0.0d0
         u3scale = 0.0d0
         u4scale = 0.0d0
      end if
c
c     print the electrostatic and polarization scale factors
c
      write (iout,10)
   10 format (/,' Electrostatic and Polarization Scale Factors :',
     &        //,20x,'1-2',9x,'1-3',9x,'1-4',9x,'1-5',/)
      write (iout,20)  m2scale,m3scale,m4scale,m5scale
   20 format (' M-Scale:',3x,4f12.4)
      write (iout,30)  p2scale,p3scale,p4scale,p5scale
   30 format (' P-Inter:',3x,4f12.4)
      write (iout,40)  p2iscale,p3iscale,p4iscale,p5iscale
   40 format (' P-Intra:',3x,4f12.4)
      write (iout,50)  w2scale,w3scale,w4scale,w5scale
   50 format (' W-Scale:',3x,4f12.4)
      write (iout,60)
   60 format (/,20x,'1-1',9x,'1-2',9x,'1-3',9x,'1-4',/)
      write (iout,70)  d1scale,d2scale,d3scale,d4scale
   70 format (' D-Scale:',3x,4f12.4)
      write (iout,80)  u1scale,u2scale,u3scale,u4scale
   80 format (' U-Scale:',3x,4f12.4)
      truth = 'False'
      if (use_thole)  truth = 'True'
      write (iout,90)  truth(1:trimtext(truth))
   90 format (/,' Use Thole Damping:',11x,a)
      truth = 'False'
      if (use_dirdamp)  truth = 'True'
      write (iout,95)  truth(1:trimtext(truth))
   95 format (/,' Use Direct Damping:',11x,a)
      truth = 'False'
      if (use_chgpen)  truth = 'True'
      write (iout,100)  truth(1:trimtext(truth))
  100 format (' Charge Penetration:',10x,a)
      truth = 'False'
      if (dpequal)  truth = 'True'
      write (iout,110)  truth(1:trimtext(truth))
  110 format (' Set D Equal to P:',12x,a)
c
c     set tolerances for computation of mutual induced dipoles
c
      done = .false.
      maxiter = 100
      iter = 0
      polmin = 0.00000001d0
      eps = 100.0d0
c
c     compute intergroup induced dipole moments via CG algorithm
c
      call ufieldi (field)
      do i = 1, npole
         poli(i) = max(polmin,polarity(i))
         do j = 1, 3
            rsd(j,i) = field(j,i)
            zrsd(j,i) = rsd(j,i) * poli(i)
            conj(j,i) = zrsd(j,i)
         end do
      end do
c
c     conjugate gradient iteration of intergroup induced dipoles
c
      do while (.not. done)
         iter = iter + 1
         do i = 1, npole
            do j = 1, 3
               vec(j,i) = uind(j,i)
               uind(j,i) = conj(j,i)
            end do
         end do
         call ufieldi (field)
         do i = 1, npole
            do j = 1, 3
               uind(j,i) = vec(j,i)
               vec(j,i) = conj(j,i)/poli(i) - field(j,i)
            end do
         end do
         a = 0.0d0
         sum = 0.0d0
         do i = 1, npole
            do j = 1, 3
               a = a + conj(j,i)*vec(j,i)
               sum = sum + rsd(j,i)*zrsd(j,i)
            end do
         end do
         if (a .ne. 0.0d0)  a = sum / a
         do i = 1, npole
            do j = 1, 3
               uind(j,i) = uind(j,i) + a*conj(j,i)
               rsd(j,i) = rsd(j,i) - a*vec(j,i)
            end do
         end do
         b = 0.0d0
         do i = 1, npole
            do j = 1, 3
               zrsd(j,i) = rsd(j,i) * poli(i)
               b = b + rsd(j,i)*zrsd(j,i)
            end do
         end do
         if (sum .ne. 0.0d0)  b = b / sum
         eps = 0.0d0
         do i = 1, npole
            do j = 1, 3
               conj(j,i) = zrsd(j,i) + b*conj(j,i)
               eps = eps + rsd(j,i)*rsd(j,i)
            end do
         end do
c
c     check the convergence of the intergroup induced dipoles
c
         eps = debye * sqrt(eps/dble(npolar))
         epsold = eps
         if (iter .eq. 1) then
            write (iout,120)
  120       format (/,' Determination of Intergroup Induced',
     &                 ' Dipoles :',
     &              //,4x,'Iter',8x,'RMS Change (Debye)',/)
         end if
         write (iout,130)  iter,eps
  130    format (i8,7x,f16.10)
         if (eps .lt. poleps)  done = .true.
         if (eps .gt. epsold)  done = .true.
         if (iter .ge. maxiter)  done = .true.
c
c     apply a "peek" iteration to the intergroup induced dipoles
c
         if (done) then
            do i = 1, npole
               term = poli(i)
               do j = 1, 3
                  uind(j,i) = uind(j,i) + term*rsd(j,i)
               end do
            end do
         end if
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (poli)
      deallocate (field)
      deallocate (rsd)
      deallocate (zrsd)
      deallocate (conj)
      deallocate (vec)
c
c     terminate the calculation if dipoles failed to converge
c
      if (eps .gt. poleps) then
         write (iout,140)
  140    format (/,' INTERPOL  --  Warning, Induced Dipoles',
     &              ' are not Converged')
         call prterr
         call fatal
      end if
c
c     rotate the induced dipoles into local coordinate frame
c
      do i = 1, npole
         call rotmat (i,rmt,planar)
         call invert (3,rmt)
         do j = 1, 3
            utmp(j) = 0.0d0
            do k = 1, 3
               utmp(j) = utmp(j) + uind(k,i)*rmt(j,k)
            end do
         end do
         do j = 1, 3
            uind(j,i) = utmp(j)
         end do
      end do
c
c     print out a list of the final induced dipole moments
c
      write (iout,150)
  150 format (/,' Local Frame Intergroup Induced Dipole Moments',
     &           ' (Debye) :')
      write (iout,160)
  160 format (/,4x,'Atom',14x,'X',11x,'Y',11x,'Z',9x,'Total',/)
      do i = 1, npole
         k = ipole(i)
         norm = sqrt(uind(1,i)**2+uind(2,i)**2+uind(3,i)**2)
         write (iout,170)  k,(debye*uind(j,i),j=1,3),debye*norm
  170    format (i8,5x,4f12.4)
      end do
      return
      end
c
c
c     ##############################################################
c     ##                                                          ##
c     ##  subroutine dfieldi  --  find permanent multipole field  ##
c     ##                                                          ##
c     ##############################################################
c
c
c     "dfieldi" computes the electrostatic field due to permanent
c     multipole moments
c
c
      subroutine dfieldi (field)
      use atoms
      use chgpen
      use couple
      use mplpot
      use mpole
      use polar
      use polgrp
      use polpot
      implicit none
      integer i,j,k
      integer ii,kk
      real*8 xr,yr,zr
      real*8 r,r2,rr3,rr5,rr7
      real*8 rr3i,rr5i,rr7i
      real*8 rr3k,rr5k,rr7k
      real*8 ci,dix,diy,diz
      real*8 qixx,qixy,qixz
      real*8 qiyy,qiyz,qizz
      real*8 ck,dkx,dky,dkz
      real*8 qkxx,qkxy,qkxz
      real*8 qkyy,qkyz,qkzz
      real*8 dir,dkr
      real*8 qix,qiy,qiz,qir
      real*8 qkx,qky,qkz,qkr
      real*8 corei,corek
      real*8 vali,valk
      real*8 alphai,alphak
      real*8 damp,expdamp
      real*8 scale3,scale5
      real*8 scale7
      real*8 pdi,pti,ddi,pgamma
      real*8 fid(3),fkd(3)
      real*8 dmpi(7),dmpk(7)
      real*8, allocatable :: dscale(:)
      real*8 field(3,*)
c
c
c     zero out the induced dipole and the field at each site
c
      do ii = 1, npole
         do j = 1, 3
            uind(j,ii) = 0.0d0
            field(j,ii) = 0.0d0
         end do
      end do
c
c     perform dynamic allocation of some local arrays
c
      allocate (dscale(n))
c
c     set array needed to scale atom and group interactions
c
      do i = 1, n
         dscale(i) = 1.0d0
      end do
c
c     find the electrostatic field due to permanent multipoles
c
      do ii = 1, npole-1
         i = ipole(ii)
         ci = rpole(1,ii)
         dix = rpole(2,ii)
         diy = rpole(3,ii)
         diz = rpole(4,ii)
         qixx = rpole(5,ii)
         qixy = rpole(6,ii)
         qixz = rpole(7,ii)
         qiyy = rpole(9,ii)
         qiyz = rpole(10,ii)
         qizz = rpole(13,ii)
         if (use_thole) then
            pdi = pdamp(ii)
            pti = thole(ii)
         else if (use_dirdamp) then
            pdi = pdamp(ii)
            pti = thole(ii)
            ddi = dirdamp(ii)
         else if (use_chgpen) then
            corei = pcore(ii)
            vali = pval(ii)
            alphai = palpha(ii)
         end if
c
c     set exclusion coefficients for connected atoms
c
         if (dpequal) then
            do j = 1, n12(i)
               dscale(i12(j,i)) = p2scale
               do k = 1, np11(i)
                  if (i12(j,i) .eq. ip11(k,i))
     &               dscale(i12(j,i)) = p2iscale
               end do
            end do
            do j = 1, n13(i)
               dscale(i13(j,i)) = p3scale
               do k = 1, np11(i)
                  if (i13(j,i) .eq. ip11(k,i))
     &               dscale(i13(j,i)) = p3iscale
               end do
            end do
            do j = 1, n14(i)
               dscale(i14(j,i)) = p4scale
               do k = 1, np11(i)
                  if (i14(j,i) .eq. ip11(k,i))
     &               dscale(i14(j,i)) = p4iscale
               end do
            end do
            do j = 1, n15(i)
               dscale(i15(j,i)) = p5scale
               do k = 1, np11(i)
                  if (i15(j,i) .eq. ip11(k,i))
     &               dscale(i15(j,i)) = p5iscale
               end do
            end do
         else
            do j = 1, np11(i)
               dscale(ip11(j,i)) = d1scale
            end do
            do j = 1, np12(i)
               dscale(ip12(j,i)) = d2scale
            end do
            do j = 1, np13(i)
               dscale(ip13(j,i)) = d3scale
            end do
            do j = 1, np14(i)
               dscale(ip14(j,i)) = d4scale
            end do
         end if
c
c     evaluate higher-numbered sites with the original site
c
         do kk = ii+1, npole
            k = ipole(kk)
            xr = x(k) - x(i)
            yr = y(k) - y(i)
            zr = z(k) - z(i)
            r2 = xr*xr + yr* yr + zr*zr
            r = sqrt(r2)
            ck = rpole(1,kk)
            dkx = rpole(2,kk)
            dky = rpole(3,kk)
            dkz = rpole(4,kk)
            qkxx = rpole(5,kk)
            qkxy = rpole(6,kk)
            qkxz = rpole(7,kk)
            qkyy = rpole(9,kk)
            qkyz = rpole(10,kk)
            qkzz = rpole(13,kk)
c
c     intermediates involving moments and separation distance
c
            dir = dix*xr + diy*yr + diz*zr
            qix = qixx*xr + qixy*yr + qixz*zr
            qiy = qixy*xr + qiyy*yr + qiyz*zr
            qiz = qixz*xr + qiyz*yr + qizz*zr
            qir = qix*xr + qiy*yr + qiz*zr
            dkr = dkx*xr + dky*yr + dkz*zr
            qkx = qkxx*xr + qkxy*yr + qkxz*zr
            qky = qkxy*xr + qkyy*yr + qkyz*zr
            qkz = qkxz*xr + qkyz*yr + qkzz*zr
            qkr = qkx*xr + qky*yr + qkz*zr
c
c     find the field components for Thole polarization damping
c
            if (use_thole) then
               damp = pdi * pdamp(kk)
               scale3 = 1.0d0
               scale5 = 1.0d0
               scale7 = 1.0d0
               if (damp .ne. 0.0d0) then
                  pgamma = min(pti,thole(kk))
                  damp = pgamma * (r/damp)**3
                  if (damp .lt. 50.0d0) then
                     expdamp = exp(-damp)
                     scale3 = 1.0d0 - expdamp
                     scale5 = 1.0d0 - expdamp*(1.0d0+damp)
                     scale7 = 1.0d0 - expdamp*(1.0d0+damp
     &                                   +0.6d0*damp**2)
                  end if
               end if
               rr3 = scale3 / (r*r2)
               rr5 = 3.0d0 * scale5 / (r*r2*r2)
               rr7 = 15.0d0 * scale7 / (r*r2*r2*r2)
               fid(1) = -xr*(rr3*ck-rr5*dkr+rr7*qkr)
     &                     - rr3*dkx + 2.0d0*rr5*qkx
               fid(2) = -yr*(rr3*ck-rr5*dkr+rr7*qkr)
     &                     - rr3*dky + 2.0d0*rr5*qky
               fid(3) = -zr*(rr3*ck-rr5*dkr+rr7*qkr)
     &                     - rr3*dkz + 2.0d0*rr5*qkz
               fkd(1) = xr*(rr3*ci+rr5*dir+rr7*qir)
     &                     - rr3*dix - 2.0d0*rr5*qix
               fkd(2) = yr*(rr3*ci+rr5*dir+rr7*qir)
     &                     - rr3*diy - 2.0d0*rr5*qiy
               fkd(3) = zr*(rr3*ci+rr5*dir+rr7*qir)
     &                     - rr3*diz - 2.0d0*rr5*qiz
c
c     find the field components for Direct polarization damping
c
            else if (use_dirdamp) then
               damp = pdi * pdamp(kk)
               scale3 = 1.0d0
               scale5 = 1.0d0
               scale7 = 1.0d0
               if (damp .ne. 0.0d0) then
                  pgamma = min(ddi,dirdamp(kk))
                  damp = pgamma * (r/damp)**(1.5d0)
                  if (damp .lt. 50.0d0) then
                     expdamp = exp(-damp)
                     scale3 = 1.0d0 - expdamp
                     scale5 = 1.0d0 - expdamp*(1.0d0+0.5d0*damp)
                     scale7 = 1.0d0 - expdamp*(1.0d0+0.65d0*damp
     &                                   +0.15d0*damp**2)
                  end if
               end if
               rr3 = scale3 / (r*r2)
               rr5 = 3.0d0 * scale5 / (r*r2*r2)
               rr7 = 15.0d0 * scale7 / (r*r2*r2*r2)
               fid(1) = -xr*(rr3*ck-rr5*dkr+rr7*qkr)
     &                     - rr3*dkx + 2.0d0*rr5*qkx
               fid(2) = -yr*(rr3*ck-rr5*dkr+rr7*qkr)
     &                     - rr3*dky + 2.0d0*rr5*qky
               fid(3) = -zr*(rr3*ck-rr5*dkr+rr7*qkr)
     &                     - rr3*dkz + 2.0d0*rr5*qkz
               fkd(1) = xr*(rr3*ci+rr5*dir+rr7*qir)
     &                     - rr3*dix - 2.0d0*rr5*qix
               fkd(2) = yr*(rr3*ci+rr5*dir+rr7*qir)
     &                     - rr3*diy - 2.0d0*rr5*qiy
               fkd(3) = zr*(rr3*ci+rr5*dir+rr7*qir)
     &                     - rr3*diz - 2.0d0*rr5*qiz
c
c     find the field components for charge penetration damping
c
            else if (use_chgpen) then
               corek = pcore(kk)
               valk = pval(kk)
               alphak = palpha(kk)
               call dampdir (r,alphai,alphak,dmpi,dmpk)
               rr3 = 1.0d0 / (r*r2)
               rr5 = 3.0d0 * rr3 / r2
               rr7 = 5.0d0 * rr5 / r2
               rr3i = dmpi(3) * rr3
               rr5i = dmpi(5) * rr5
               rr7i = dmpi(7) * rr7
               rr3k = dmpk(3) * rr3
               rr5k = dmpk(5) * rr5
               rr7k = dmpk(7) * rr7
               fid(1) = -xr*(rr3*corek + rr3k*valk
     &                     - rr5k*dkr + rr7k*qkr)
     &                     - rr3k*dkx + 2.0d0*rr5k*qkx
               fid(2) = -yr*(rr3*corek + rr3k*valk
     &                     - rr5k*dkr + rr7k*qkr)
     &                     - rr3k*dky + 2.0d0*rr5k*qky
               fid(3) = -zr*(rr3*corek + rr3k*valk
     &                     - rr5k*dkr + rr7k*qkr)
     &                     - rr3k*dkz + 2.0d0*rr5k*qkz
               fkd(1) = xr*(rr3*corei + rr3i*vali
     &                     + rr5i*dir + rr7i*qir)
     &                     - rr3i*dix - 2.0d0*rr5i*qix
               fkd(2) = yr*(rr3*corei + rr3i*vali
     &                     + rr5i*dir + rr7i*qir)
     &                     - rr3i*diy - 2.0d0*rr5i*qiy
               fkd(3) = zr*(rr3*corei + rr3i*vali
     &                     + rr5i*dir + rr7i*qir)
     &                     - rr3i*diz - 2.0d0*rr5i*qiz
            end if
            do j = 1, 3
               field(j,ii) = field(j,ii) + fid(j)*dscale(k)
               field(j,kk) = field(j,kk) + fkd(j)*dscale(k)
            end do
         end do
c
c     reset exclusion coefficients for connected atoms
c
         if (dpequal) then
            do j = 1, n12(i)
               dscale(i12(j,i)) = 1.0d0
            end do
            do j = 1, n13(i)
               dscale(i13(j,i)) = 1.0d0
            end do
            do j = 1, n14(i)
               dscale(i14(j,i)) = 1.0d0
            end do
            do j = 1, n15(i)
               dscale(i15(j,i)) = 1.0d0
            end do
         else
            do j = 1, np11(i)
               dscale(ip11(j,i)) = 1.0d0
            end do
            do j = 1, np12(i)
               dscale(ip12(j,i)) = 1.0d0
            end do
            do j = 1, np13(i)
               dscale(ip13(j,i)) = 1.0d0
            end do
            do j = 1, np14(i)
               dscale(ip14(j,i)) = 1.0d0
            end do
         end if
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (dscale)
      return
      end
c
c
c     #############################################################
c     ##                                                         ##
c     ##  subroutine ufieldi  --  find induced intergroup field  ##
c     ##                                                         ##
c     #############################################################
c
c
c     "ufieldi" computes the electrostatic field due to intergroup
c     induced dipole moments
c
c     literature reference:
c
c     P. Ren and J. W. Ponder, "Consistent Treatment of Inter- and
c     Intramolecular Polarization in Molecular Mechanics Calculations",
c     Journal of Computational Chemistry, 23, 1497-1506 (2002)
c
c
      subroutine ufieldi (field)
      use atoms
      use chgpen
      use couple
      use mplpot
      use mpole
      use polar
      use polgrp
      use polpot
      implicit none
      integer i,j,k
      integer ii,kk
      real*8 xr,yr,zr
      real*8 r,r2,rr3,rr5
      real*8 uix,uiy,uiz
      real*8 ukx,uky,ukz
      real*8 uir,ukr
      real*8 corei,corek
      real*8 vali,valk
      real*8 alphai,alphak
      real*8 damp,expdamp
      real*8 scale3,scale5
      real*8 pdi,pti,pgamma
      real*8 fiu(3),fku(3)
      real*8 dmpik(5)
      real*8, allocatable :: dscale(:)
      real*8, allocatable :: pscale(:)
      real*8, allocatable :: uscale(:)
      real*8, allocatable :: wscale(:)
      real*8, allocatable :: gscale(:)
      real*8 field(3,*)
c
c
c     zero out the value of the field at each site
c
      do i = 1, npole
         do j = 1, 3
            field(j,i) = 0.0d0
         end do
      end do
c
c     perform dynamic allocation of some local arrays
c
      allocate (dscale(n))
      allocate (pscale(n))
      allocate (uscale(n))
      allocate (wscale(n))
      allocate (gscale(n))
c
c     set arrays needed to scale atom and group interactions
c
      do i = 1, n
         dscale(i) = 1.0d0
         pscale(i) = 1.0d0
         uscale(i) = 1.0d0
         wscale(i) = 1.0d0
         gscale(i) = 0.0d0
      end do
c
c     find the electrostatic field due to induced dipoles
c
      do ii = 1, npole-1
         i = ipole(ii)
         uix = uind(1,ii)
         uiy = uind(2,ii)
         uiz = uind(3,ii)
         if (use_thole) then
            pdi = pdamp(ii)
            pti = thole(ii)
         else if (use_dirdamp) then
            pdi = pdamp(ii)
            pti = thole(ii)
         else if (use_chgpen) then
            corei = pcore(ii)
            vali = pval(ii)
            alphai = palpha(ii)
         end if
c
c     set exclusion coefficients for connected atoms
c
         if (dpequal) then
            if (use_chgpen) then
               do j = 1, n12(i)
                  gscale(i12(j,i)) = w2scale - p2scale
                  do k = 1, np11(i)
                     if (i12(j,i) .eq. ip11(k,i))
     &                  gscale(i12(j,i)) = w2scale - p2iscale
                  end do
               end do
               do j = 1, n13(i)
                  gscale(i13(j,i)) = w3scale - p3scale
                  do k = 1, np11(i)
                     if (i13(j,i) .eq. ip11(k,i))
     &                  gscale(i13(j,i)) = w3scale - p3iscale
                  end do
               end do
               do j = 1, n14(i)
                  gscale(i14(j,i)) = w4scale - p4scale
                  do k = 1, np11(i)
                     if (i14(j,i) .eq. ip11(k,i))
     &                  gscale(i14(j,i)) = w4scale - p4iscale
                  end do
               end do
               do j = 1, n15(i)
                  gscale(i15(j,i)) = w5scale - p5scale
                  do k = 1, np11(i)
                     if (i15(j,i) .eq. ip11(k,i))
     &                  gscale(i15(j,i)) = w5scale - p5iscale
                  end do
               end do
            else
               do j = 1, n12(i)
                  pscale(i12(j,i)) = p2scale
                  do k = 1, np11(i)
                     if (i12(j,i) .eq. ip11(k,i))
     &                  pscale(i12(j,i)) = p2iscale
                  end do
               end do
               do j = 1, n13(i)
                  pscale(i13(j,i)) = p3scale
                  do k = 1, np11(i)
                     if (i13(j,i) .eq. ip11(k,i))
     &                  pscale(i13(j,i)) = p3iscale
                  end do
               end do
               do j = 1, n14(i)
                  pscale(i14(j,i)) = w4scale
                  do k = 1, np11(i)
                     if (i14(j,i) .eq. ip11(k,i))
     &                  pscale(i14(j,i)) = p4iscale
                  end do
               end do
               do j = 1, n15(i)
                  pscale(i15(j,i)) = p5scale
                  do k = 1, np11(i)
                     if (i15(j,i) .eq. ip11(k,i))
     &                  pscale(i15(j,i)) = p5iscale
                  end do
               end do
               do j = 1, np11(i)
                  uscale(ip11(j,i)) = u1scale
               end do
               do j = 1, np12(i)
                  uscale(ip12(j,i)) = u2scale
               end do
               do j = 1, np13(i)
                  uscale(ip13(j,i)) = u3scale
               end do
               do j = 1, np14(i)
                  uscale(ip14(j,i)) = u4scale
               end do
               do j = ii+1, npole
                  k = ipole(j)
                  gscale(k) = uscale(k) - pscale(k)
               end do
            end if
         else
            if (use_chgpen) then
               do j = 1, n12(i)
                  wscale(i12(j,i)) = w2scale
               end do
               do j = 1, n13(i)
                  wscale(i13(j,i)) = w3scale
               end do
               do j = 1, n14(i)
                  wscale(i14(j,i)) = w4scale
               end do
               do j = 1, n15(i)
                  wscale(i15(j,i)) = w5scale
               end do
               do j = 1, np11(i)
                  dscale(ip11(j,i)) = d1scale
               end do
               do j = 1, np12(i)
                  dscale(ip12(j,i)) = d2scale
               end do
               do j = 1, np13(i)
                  dscale(ip13(j,i)) = d3scale
               end do
               do j = 1, np14(i)
                  dscale(ip14(j,i)) = d4scale
               end do
               do j = ii+1, npole
                  k = ipole(j)
                  gscale(k) = wscale(k) - dscale(k)
               end do
            else
               do j = 1, np11(i)
                  gscale(ip11(j,i)) = u1scale - d1scale
               end do
               do j = 1, np12(i)
                  gscale(ip12(j,i)) = u2scale - d2scale
               end do
               do j = 1, np13(i)
                  gscale(ip13(j,i)) = u3scale - d3scale
               end do
               do j = 1, np14(i)
                  gscale(ip14(j,i)) = u4scale - d4scale
               end do
            end if
         end if
c
c     evaluate higher-numbered sites with the original site
c
         do kk = ii+1, npole
            k = ipole(kk)
            xr = x(k) - x(i)
            yr = y(k) - y(i)
            zr = z(k) - z(i)
            r2 = xr*xr + yr* yr + zr*zr
            r = sqrt(r2)
            ukx = uind(1,kk)
            uky = uind(2,kk)
            ukz = uind(3,kk)
c
c     intermediates involving moments and separation distance
c
            uir = xr*uix + yr*uiy + zr*uiz
            ukr = xr*ukx + yr*uky + zr*ukz
c
c     find the field components for Thole polarization damping
c
            if (use_thole .or. use_dirdamp) then
               scale3 = 1.0d0
               scale5 = 1.0d0
               damp = pdi * pdamp(kk)
               if (damp .ne. 0.0d0) then
                  pgamma = min(pti,thole(kk))
                  damp = pgamma * (r/damp)**3
                  if (damp .lt. 50.0d0) then
                     expdamp = exp(-damp)
                     scale3 = 1.0d0 - expdamp
                     scale5 = 1.0d0 - expdamp*(1.0d0+damp)
                  end if
               end if
c
c     find the field components for charge penetration damping
c
            else if (use_chgpen) then
               corek = pcore(kk)
               valk = pval(kk)
               alphak = palpha(kk)
               call dampmut (r,alphai,alphak,dmpik)
               scale3 = dmpik(3)
               scale5 = dmpik(5)
            end if
            rr3 = -scale3 / (r*r2)
            rr5 = 3.0d0 * scale5 / (r*r2*r2)
            fiu(1) = rr3*ukx + rr5*ukr*xr
            fiu(2) = rr3*uky + rr5*ukr*yr
            fiu(3) = rr3*ukz + rr5*ukr*zr
            fku(1) = rr3*uix + rr5*uir*xr
            fku(2) = rr3*uiy + rr5*uir*yr
            fku(3) = rr3*uiz + rr5*uir*zr
            do j = 1, 3
               field(j,ii) = field(j,ii) + fiu(j)*gscale(k)
               field(j,kk) = field(j,kk) + fku(j)*gscale(k)
            end do
         end do
c
c     reset exclusion coefficients for connected atoms
c
         if (dpequal) then
            if (use_chgpen) then
               do j = 1, n12(i)
                  gscale(i12(j,i)) = 0.0d0
               end do
               do j = 1, n13(i)
                  gscale(i13(j,i)) = 0.0d0
               end do
               do j = 1, n14(i)
                  gscale(i14(j,i)) = 0.0d0
               end do
               do j = 1, n15(i)
                  gscale(i15(j,i)) = 0.0d0
               end do
            else
               do j = 1, np11(i)
                  uscale(ip11(j,i)) = 1.0d0
                  gscale(ip11(j,i)) = 0.0d0
               end do
               do j = 1, np12(i)
                  uscale(ip12(j,i)) = 1.0d0
                  gscale(ip12(j,i)) = 0.0d0
               end do
               do j = 1, np13(i)
                  uscale(ip13(j,i)) = 1.0d0
                  gscale(ip13(j,i)) = 0.0d0
               end do
               do j = 1, np14(i)
                  uscale(ip14(j,i)) = 1.0d0
                  gscale(ip14(j,i)) = 0.0d0
               end do
               do j = 1, n12(i)
                  pscale(i12(j,i)) = 1.0d0
                  gscale(i12(j,i)) = 0.0d0
               end do
               do j = 1, n13(i)
                  pscale(i13(j,i)) = 1.0d0
                  gscale(i13(j,i)) = 0.0d0
               end do
               do j = 1, n14(i)
                  pscale(i14(j,i)) = 1.0d0
                  gscale(i14(j,i)) = 0.0d0
               end do
               do j = 1, n15(i)
                  pscale(i15(j,i)) = 1.0d0
                  gscale(i15(j,i)) = 0.0d0
               end do
            end if
         else
            if (use_chgpen) then
               do j = 1, np11(i)
                  dscale(ip11(j,i)) = 1.0d0
                  gscale(ip11(j,i)) = 0.0d0
               end do
               do j = 1, np12(i)
                  dscale(ip12(j,i)) = 1.0d0
                  gscale(ip12(j,i)) = 0.0d0
               end do
               do j = 1, np13(i)
                  dscale(ip13(j,i)) = 1.0d0
                  gscale(ip13(j,i)) = 0.0d0
               end do
               do j = 1, np14(i)
                  dscale(ip14(j,i)) = 1.0d0
                  gscale(ip14(j,i)) = 0.0d0
               end do
               do j = 1, n12(i)
                  wscale(i12(j,i)) = 1.0d0
                  gscale(i12(j,i)) = 0.0d0
               end do
               do j = 1, n13(i)
                  wscale(i13(j,i)) = 1.0d0
                  gscale(i13(j,i)) = 0.0d0
               end do
               do j = 1, n14(i)
                  wscale(i14(j,i)) = 1.0d0
                  gscale(i14(j,i)) = 0.0d0
               end do
               do j = 1, n15(i)
                  wscale(i15(j,i)) = 1.0d0
                  gscale(i15(j,i)) = 0.0d0
               end do
            else
               do j = 1, np11(i)
                  gscale(ip11(j,i)) = 0.0d0
               end do
               do j = 1, np12(i)
                  gscale(ip12(j,i)) = 0.0d0
               end do
               do j = 1, np13(i)
                  gscale(ip13(j,i)) = 0.0d0
               end do
               do j = 1, np14(i)
                  gscale(ip14(j,i)) = 0.0d0
               end do
            end if
         end if
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (dscale)
      deallocate (pscale)
      deallocate (uscale)
      deallocate (wscale)
      deallocate (gscale)
      return
      end
c
c
c     #############################################################
c     ##                                                         ##
c     ##  subroutine avgpole  --  condense multipole atom types  ##
c     ##                                                         ##
c     #############################################################
c
c
c     "avgpole" condenses the number of multipole atom types based
c     upon atoms with equivalent attachments and additional user
c     specified sets of equivalent atoms
c
c
      subroutine avgpole
      use atomid
      use atoms
      use couple
      use iounit
      use kpolr
      use mpole
      use sizes
      implicit none
      integer i,j,k,m
      integer it,mt
      integer in,jn,ni,nj
      integer size,numtyp
      integer nlist,nave
      integer tmin,tmax
      integer xaxe,yaxe,zaxe
      integer, allocatable :: ci(:)
      integer, allocatable :: cj(:)
      integer, allocatable :: list(:)
      integer, allocatable :: tsort(:)
      integer, allocatable :: pkey(:)
      integer, allocatable :: pgrt(:,:)
      real*8 pave(13)
      logical done,header,exist
      logical query,condense
      logical match,diff
      logical useframe,symm
      logical yzero,xyzero
      character*1 answer
      character*4 pa,pb,pc,pd
      character*16 ptlast
      character*16, allocatable :: pt(:)
      character*240 record
      character*240 string
c
c
c     check for user requested reduction of equivalent types
c
      condense = .true.
      answer = 'Y'
      query = .true.
      call nextarg (string,exist)
      if (exist) then
         read (string,*,err=10,end=10)  answer
         query = .false.
      end if
   10 continue
      if (query) then
         write (iout,20)
   20    format (/,' Condense Symmetric Atoms to Equivalent Types',
     &              ' [Y] :  ',$)
         read (input,30)  answer
   30    format (a1)
      end if
      call upcase (answer)
      if (answer .eq. 'N')  condense = .false.
c
c     perform dynamic allocation of some local arrays
c
      if (condense) then
         allocate (ci(n))
         allocate (cj(n))
         size = 40
         allocate (list(max(n,size)))
c
c     condense groups of equivalent atoms to the same atom type
c
         header = .true.
         do i = 1, n
            list(i) = 0
         end do
         do i = 1, n-1
            ni = n12(i) + n13(i) + n14(i) + n15(i)
            m = 0
            do k = 1, n12(i)
               m = m + 1
               in = i12(k,i)
               ci(m) = 2000 + 10*atomic(in) + n12(in)
            end do
            do k = 1, n13(i)
               m = m + 1
               in = i13(k,i)
               ci(m) = 3000 + 10*atomic(in) + n12(in)
            end do
            do k = 1, n14(i)
               m = m + 1
               in = i14(k,i)
               ci(m) = 4000 + 10*atomic(in) + n12(in)
            end do
            do k = 1, n15(i)
               m = m + 1
               in = i15(k,i)
               ci(m) = 5000 + 10*atomic(in) + n12(in)
            end do
            call sort (ni,ci)
            do j = i+1, n
               if (atomic(i) .eq. atomic(j)) then
                  nj = n12(j) + n13(j) + n14(j) + n15(j)
                  if (nj .eq. ni) then
                     m = 0
                     do k = 1, n12(j)
                        m = m + 1
                        jn = i12(k,j)
                        cj(m) = 2000 + 10*atomic(jn) + n12(jn)
                     end do
                     do k = 1, n13(j)
                        m = m + 1
                        jn = i13(k,j)
                        cj(m) = 3000 + 10*atomic(jn) + n12(jn)
                     end do
                     do k = 1, n14(j)
                        m = m + 1
                        jn = i14(k,j)
                        cj(m) = 4000 + 10*atomic(jn) + n12(jn)
                     end do
                     do k = 1, n15(j)
                        m = m + 1
                        jn = i15(k,j)
                        cj(m) = 5000 + 10*atomic(jn) + n12(jn)
                     end do
                     call sort (nj,cj)
                     match = .true.
                     do k = 1, ni
                        if (ci(k) .ne. cj(k)) then
                           match = .false.
                           goto 40
                        end if
   40                   continue
                     end do
                     if (match) then
                        tmin = min(type(i),type(j))
                        tmax = max(type(i),type(j))
                        do k = 1, n
                           if (type(k) .eq. tmax)  type(k) = tmin
                        end do
                        if (list(i).eq.0 .or. list(j).eq.0) then
                           if (header) then
                              header = .false.
                              write (iout,50)
   50                         format (/,' Equivalent Atoms Assigned',
     &                                   ' the Same Atom Type :',/)
                           end if
                           write (iout,60)  i,j
   60                      format (' Atoms',i6,2x,'and',i6,2x,
     &                                'Set to Equivalent Types')
                           list(i) = 1
                           list(j) = 1
                        end if
                     end if
                  end if
               end if
            end do
         end do
c
c     perform deallocation of some local arrays
c
         deallocate (ci)
         deallocate (cj)
c
c     perform dynamic allocation of some local arrays
c
         allocate (tsort(n))
         allocate (pkey(n))
         allocate (pt(n))
c
c     count the number of distinct atom types in the system
c
         numtyp = 0
         do i = 1, n
            numtyp = max(numtyp,type(i))
         end do
c
c     query for more atom sets to condense to a single type
c
         done = .false.
         dowhile (.not. done)
            do i = 1, size
               list(i) = 0
            end do
            write (iout,70)
   70       format (/,' Enter Sets of Equivalent or Different',
     &                 ' Atoms [<Enter>=Exit] :  ',$)
            read (input,80)  record
   80       format (a240)
            read (record,*,err=90,end=90)  (list(i),i=1,size)
   90       continue
c
c     add or remove the equivalence of specified sets of atoms
c
            diff = .false.
            nlist = 1
            if (list(1) .ne. 0)  k = type(list(1))
            dowhile (list(nlist) .ne. 0)
               if (type(list(nlist)) .ne. k)  diff = .true.
               nlist = nlist + 1
            end do
            nlist = nlist - 1
            if (nlist .eq. 0) then
               done = .true.
            else if (diff) then
               tmin = n + 1
               do i = 1, nlist
                  tmin = min(tmin,type(list(i)))
               end do
               do i = 1, nlist
                  k = type(list(i))
                  if (k .ne. tmin) then
                     tmax = k
                     do k = 1, n
                        if (type(k) .eq. tmax)  type(k) = tmin
                     end do
                  end if
               end do
            else
               do i = 1, nlist
                  numtyp = numtyp + 1
                  type(list(i)) = numtyp
               end do
            end if
         end do
c
c     renumber the atom types to give consecutive ordering
c
         do i = 1, n
            tsort(i) = 0
         end do
         m = 0
         do i = 1, n
            k = type(i)
            if (tsort(k) .eq. 0) then
               tsort(k) = i
               m = m + 1
               type(i) = m
            else
               type(i) = type(tsort(k))
            end if
         end do
c
c     print the atoms, atom types and local frame definitions
c
         write (iout,100)
  100    format (/,' Atom Type and Local Frame Definition',
     &              ' for Each Atom :',
     &           //,5x,'Atom',4x,'Type',6x,'Local Frame',10x,
     &              'Frame Defining Atoms',/)
         do i = 1, n
            k = pollist(i)
            write (iout,110)  i,type(i),polaxe(k),zaxis(k),
     &                        xaxis(k),yaxis(k)
  110       format (2i8,9x,a8,6x,3i8)
         end do
c
c     identify atoms with the same atom type number, or find
c     atoms with equivalent local frame defining atom types
c
         useframe = .false.
         do i = 1, npole
            it = type(ipole(i))
            zaxe = 0
            xaxe = 0
            yaxe = 0
            if (useframe) then
               if (zaxis(i) .ne. 0)  zaxe = type(zaxis(i))
               if (xaxis(i) .ne. 0)  xaxe = type(xaxis(i))
               if (yaxis(i) .ne. 0)  yaxe = type(yaxis(i))
            end if
            size = 4
            call numeral (it,pa,size)
            call numeral (zaxe,pb,size)
            call numeral (xaxe,pc,size)
            call numeral (yaxe,pd,size)
            pt(i) = pa//pb//pc//pd
         end do
         call sort7 (npole,pt,pkey)
c
c     average the multipole values at equivalent atom sites
c
         nave = 1
         ptlast = '                '
         do i = 1, npole
            it = pkey(i)
            if (pt(i) .eq. ptlast) then
               nave = nave + 1
               do j = 1, 13
                  pave(j) = pave(j) + pole(j,it)
               end do
               if (i .eq. npole) then
                  do j = 1, 13
                     pave(j) = pave(j) / dble(nave)
                  end do
                  do m = 1, nave
                     mt = pkey(i-m+1)
                     do j = 1, 13
                        pole(j,mt) = pave(j)
                     end do
                  end do
               end if
            else
               if (nave .ne. 1) then
                  do j = 1, 13
                     pave(j) = pave(j) / dble(nave)
                  end do
                  do m = 1, nave
                     mt = pkey(i-m)
                     do j = 1, 13
                        pole(j,mt) = pave(j)
                     end do
                  end do
               end if
               nave = 1
               do j = 1, 13
                  pave(j) = pole(j,it)
               end do
               ptlast = pt(i)
            end if
         end do
c
c     perform deallocation of some local arrays
c
         deallocate (list)
         deallocate (tsort)
         deallocate (pkey)
         deallocate (pt)
      end if
c
c     perform dynamic allocation of some local arrays
c
      allocate (pgrt(maxval,n))
c
c     set polarization groups over the condensed atom types
c
      do i = 1, n
         do j = 1, maxval
            pgrt(j,i) = 0
         end do
      end do
      do i = 1, npole
         it = type(ipole(i))
         k = 0
         do j = 1, maxval
            if (pgrp(j,i) .ne. 0) then
               k = j
               pgrp(j,it) = type(pgrp(j,i))
            else
               pgrp(j,it) = 0
            end if
         end do
         call sort8 (k,pgrp(1,it))
         do j = 1, k
            do m = 1, maxval
               if (pgrt(m,it) .eq. 0) then
                  pgrt(m,it) = pgrp(j,it)
                  goto 120
               end if
            end do
  120       continue
         end do
      end do
      do i = 1, npole
         it = type(ipole(i))
         do j = 1, maxval
            pgrp(j,it) = pgrt(j,it)
            if (pgrp(j,it) .ne. 0)  k = j
         end do
         call sort8 (k,pgrp(1,it))
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (pgrt)
c
c     regularize the multipole moments to standardized values
c
      call fixpole
c
c     check for user requested zeroing of moments by symmetry
c
      symm = .true.
      answer = 'Y'
      query = .true.
      call nextarg (string,exist)
      if (exist) then
         read (string,*,err=130,end=130)  answer
         query = .false.
      end if
  130 continue
      if (query) then
         write (iout,140)
  140    format (/,' Remove Multipole Components Zeroed by',
     &              ' Symmetry [Y] :  ',$)
         read (input,150)  answer
  150    format (a1)
      end if
      call upcase (answer)
      if (answer .eq. 'N')  symm = .false.
c
c     remove multipole components that are zero by symmetry
c
      if (symm) then
         do i = 1, npole
            xyzero = .false.
            yzero = .false.
            if (polaxe(i) .eq. 'Bisector')  xyzero = .true.
            if (polaxe(i) .eq. 'Z-Bisect')  yzero = .true.
            if (polaxe(i) .eq. 'Z-then-X') then
               if (yaxis(i) .eq. 0)  yzero = .true.
            end if
            if (polaxe(i) .eq. 'None') then
               do j = 2, 13
                  pole(j,i) = 0.0d0
               end do
            end if
            if (polaxe(i) .eq. 'Z-Only') then
               pole(2,i) = 0.0d0
               pole(3,i) = 0.0d0
               pole(5,i) = -0.5d0 * pole(13,i)
               pole(6,i) = 0.0d0
               pole(7,i) = 0.0d0
               pole(8,i) = 0.0d0
               pole(9,i) = pole(5,i)
               pole(10,i) = 0.0d0
               pole(11,i) = 0.0d0
               pole(12,i) = 0.0d0
            end if
            if (xyzero) then
               pole(2,i) = 0.0d0
               pole(3,i) = 0.0d0
               pole(6,i) = 0.0d0
               pole(7,i) = 0.0d0
               pole(8,i) = 0.0d0
               pole(10,i) = 0.0d0
               pole(11,i) = 0.0d0
               pole(12,i) = 0.0d0
            end if
            if (yzero) then
               pole(3,i) = 0.0d0
               pole(6,i) = 0.0d0
               pole(8,i) = 0.0d0
               pole(10,i) = 0.0d0
               pole(12,i) = 0.0d0
            end if
         end do
      end if
c
c     print the final multipole values for force field use
c
      write (iout,160)
  160 format (/,' Final Atomic Multipole Moments after',
     &           ' Regularization :')
      do i = 1, n
         k = pollist(i)
         if (k .eq. 0) then
            write (iout,170)  i,name(i),atomic(i)
  170       format (/,' Atom:',i8,9x,'Name:',3x,a3,
     &                 7x,'Atomic Number:',i8)
            write (iout,180)
  180       format (/,' No Atomic Multipole Moments for this Site')
         else
            zaxe = zaxis(k)
            xaxe = xaxis(k)
            yaxe = yaxis(k)
            if (yaxe .lt. 0)  yaxe = -yaxe
            write (iout,190)  i,name(i),atomic(i)
  190       format (/,' Atom:',i8,9x,'Name:',3x,a3,
     &                 7x,'Atomic Number:',i8)
            write (iout,200)  polaxe(k),zaxe,xaxe,yaxe
  200       format (/,' Local Frame:',12x,a8,6x,3i8)
            write (iout,210)  pole(1,k)
  210       format (/,' Charge:',10x,f15.5)
            write (iout,220)  pole(2,k),pole(3,k),pole(4,k)
  220       format (' Dipole:',10x,3f15.5)
            write (iout,230)  pole(5,k)
  230       format (' Quadrupole:',6x,f15.5)
            write (iout,240)  pole(8,k),pole(9,k)
  240       format (18x,2f15.5)
            write (iout,250)  pole(11,k),pole(12,k),pole(13,k)
  250       format (18x,3f15.5)
         end if
      end do
      return
      end
c
c
c     ################################################################
c     ##                                                            ##
c     ##  subroutine fixpole  --  regularize the multipole moments  ##
c     ##                                                            ##
c     ################################################################
c
c
c     "fixpole" performs unit conversion of the multipole components,
c     rounds moments to desired precision, and enforces integer net
c     charge and traceless quadrupoles
c
c
      subroutine fixpole
      use atoms
      use mpole
      use units
      implicit none
      integer i,j,k,m
      integer it,ktype
      integer, allocatable :: equiv(:)
      real*8 eps,sum,big
      real*8 ival,kval
c
c
c     convert dipole and quadrupole moments to atomic units
c
      do i = 1, npole
         pole(1,i) = pole(1,i)
         do j = 2, 4
            pole(j,i) = pole(j,i) / bohr
         end do
         do j = 5, 13
            pole(j,i) = 3.0d0 * pole(j,i) / bohr**2
         end do
      end do
c
c     regularize multipole moments to desired precision
c
      eps = 0.00001d0
      do i = 1, npole
         do j = 1, 13
            pole(j,i) = dble(nint(pole(j,i)/eps)) * eps
         end do
      end do
c
c     perform dynamic allocation of some local arrays
c
      allocate (equiv(maxtyp))
c
c     enforce integer net charge over atomic multipoles
c
      do i = 1, maxtyp
         equiv(i) = 0
      end do
      ktype = 0
      sum = 0.0d0
      do i = 1, npole
         it = type(ipole(i))
         equiv(it) = equiv(it) + 1 
         sum = sum + pole(1,i)
      end do
      sum = sum - dble(nint(sum))
      k = nint(abs(sum)/eps)
      do j = 1, k
         m = k / j
         if (k .eq. m*j) then
            do i = 1, npole
               it = type(ipole(i))
               if (equiv(it) .eq. m) then
                  ival = abs(pole(1,ipole(i)))
                  if (ktype .eq. 0) then
                     ktype = it
                     kval = ival
                  else if (ival .gt. kval) then
                     ktype = it
                     kval = ival
                  end if
               end if
            end do
         end if
         if (ktype .ne. 0)  goto 10
      end do
   10 continue
      if (ktype .ne. 0) then
         sum = sum / dble(m)
         do i = 1, npole
            it = type(ipole(i))
            if (it .eq. ktype)  pole(1,i) = pole(1,i) - sum
         end do
      end if
c
c     perform deallocation of some local arrays
c
      deallocate (equiv)
c
c     enforce traceless quadrupole at each multipole site
c
      do i = 1, npole
         sum = pole(5,i) + pole(9,i) + pole(13,i)
         big = max(abs(pole(5,i)),abs(pole(9,i)),abs(pole(13,i)))
         k = 0
         if (big .eq. abs(pole(5,i)))  k = 5
         if (big .eq. abs(pole(9,i)))  k = 9
         if (big .eq. abs(pole(13,i)))  k = 13
         if (k .ne. 0)  pole(k,i) = pole(k,i) - sum
      end do
      return
      end
c
c
c     #################################################################
c     ##                                                             ##
c     ##  subroutine prtpole  --  create file with final multipoles  ##
c     ##                                                             ##
c     #################################################################
c
c
c     "prtpole" creates a coordinates file, and a key file with
c     atomic multipoles corrected for intergroup polarization
c
c
      subroutine prtpole
      use atoms
      use atomid
      use chgpen
      use files
      use keys
      use kpolr
      use mplpot
      use mpole
      use polar
      use polpot
      use sizes
      use units
      implicit none
      integer i,j,k,it
      integer ixyz,ikey
      integer size,tmax
      integer xaxe
      integer yaxe
      integer zaxe
      integer freeunit
      integer trimtext
      integer, allocatable :: pkey(:)
      character*4 pa,pb,pc,pd
      character*16 ptlast
      character*16, allocatable :: pt(:)
      character*240 keyfile
      character*240 record
c
c
c     create a file with coordinates and connectivities
c
      ixyz = freeunit ()
      call prtxyz (ixyz)
c
c     output some definitions and parameters to a keyfile
c
      ikey = freeunit ()
      keyfile = filename(1:leng)//'.key'
      call version (keyfile,'new')
      open (unit=ikey,file=keyfile,status='new')
c
c     copy the contents of any previously existing keyfile
c
      do i = 1, nkey
         record = keyline(i)
         size = trimtext (record)
         write (ikey,10)  record(1:size)
   10    format (a)
      end do
      if (nkey .ne. 0) then
         write (ikey,20)
   20    format ()
      end if
c
c     output the atom definitions to the keyfile as appropriate
c
      tmax = 0
      do i = 1, n
         it = type(ipole(i))
         if (it .gt. tmax) then
            write (ikey,30)  type(i),type(i),name(i),story(i),
     &                       atomic(i),mass(i),valence(i)
   30       format ('atom',6x,2i5,4x,a3,3x,'"',a20,'"',i10,f10.3,i5)
         end if
         tmax = max(it,tmax)
      end do
      if (n .ne. 0) then
         write (ikey,40)
   40    format ()
      end if
c
c     perform dynamic allocation of some local arrays
c
      allocate (pt(npole))
      allocate (pkey(npole))
c
c     locate the equivalently defined multipole sites
c
      do i = 1, npole
         k = ipole(i)
         it = type(k)
         zaxe = 0
         xaxe = 0
         yaxe = 0
         if (zaxis(i) .ne. 0)  zaxe = type(zaxis(i))
         if (xaxis(i) .ne. 0)  xaxe = type(xaxis(i))
         if (yaxis(i) .ne. 0)  yaxe = type(yaxis(i))
         size = 4
         call numeral (it,pa,size)
         call numeral (zaxe,pb,size)
         call numeral (xaxe,pc,size)
         call numeral (yaxe,pd,size)
         pt(i) = pa//pb//pc//pd
      end do
      call sort7 (npole,pt,pkey)
c
c     output the local frame multipole values to the keyfile
c
      ptlast = '                '
      do k = 1, npole
         i = pkey(k)
         it = type(ipole(i))
         if (pt(k) .ne. ptlast) then
            ptlast = pt(k)
            zaxe = 0
            xaxe = 0
            yaxe = 0
            if (zaxis(i) .ne. 0)  zaxe = type(zaxis(i))
            if (xaxis(i) .ne. 0)  xaxe = type(xaxis(i))
            if (yaxis(i) .ne. 0)  yaxe = type(yaxis(i))
            if (polaxe(i) .eq. 'None') then
               write (ikey,50)  it,pole(1,i)
   50          format ('multipole',1x,i5,21x,f11.5)
            else if (polaxe(i) .eq. 'Z-Only') then
               write (ikey,60)  it,zaxe,pole(1,i)
   60          format ('multipole',1x,2i5,16x,f11.5)
            else if (polaxe(i) .eq. 'Z-then-X') then
               if (yaxis(i) .eq. 0) then
                  write (ikey,70)  it,zaxe,xaxe,pole(1,i)
   70             format ('multipole',1x,3i5,11x,f11.5)
               else
                  write (ikey,80)  it,zaxe,xaxe,yaxe,pole(1,i)
   80             format ('multipole',1x,4i5,6x,f11.5)
               end if
            else if (polaxe(i) .eq. 'Bisector') then
               if (yaxis(i) .eq. 0) then
                  write (ikey,90)  it,-zaxe,-xaxe,pole(1,i)
   90             format ('multipole',1x,3i5,11x,f11.5)
               else
                  write (ikey,100)  it,-zaxe,-xaxe,yaxe,pole(1,i)
  100             format ('multipole',1x,4i5,6x,f11.5)
               end if
            else if (polaxe(i) .eq. 'Z-Bisect') then
               write (ikey,110)  it,zaxe,-xaxe,-yaxe,pole(1,i)
  110          format ('multipole',1x,4i5,6x,f11.5)
            else if (polaxe(i) .eq. '3-Fold') then
               write (ikey,120)  it,-zaxe,-xaxe,-yaxe,pole(1,i)
  120          format ('multipole',1x,4i5,6x,f11.5)
            end if
            write (ikey,130)  pole(2,i),pole(3,i),pole(4,i)
  130       format (36x,3f11.5)
            write (ikey,140)  pole(5,i)
  140       format (36x,f11.5)
            write (ikey,150)  pole(8,i),pole(9,i)
  150       format (36x,2f11.5)
            write (ikey,160)  pole(11,i),pole(12,i),pole(13,i)
  160       format (36x,3f11.5)
         end if
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (pt)
      deallocate (pkey)
c
c     output any charge penetration parameters to the keyfile
c
      if (use_chgpen) then
         if (n .ne. 0) then
            write (ikey,170)
  170       format ()
         end if
         tmax = 0
         do i = 1, npole
            it = type(ipole(i))
            if (it .gt. tmax) then
               write (ikey,180)  it,pcore(i),palpha(i)
  180          format ('chgpen',9x,i5,5x,2f11.4)
            end if
            tmax = max(it,tmax)
         end do
      end if
c
c     output the polarizability parameters to the keyfile
c
      if (n .ne. 0) then
         write (ikey,190)
  190    format ()
      end if
      tmax = 0
      do i = 1, npole
         it = type(ipole(i))
         if (it .gt. tmax) then
            k = 0
            do j = 1, maxval
               if (pgrp(j,it) .ne. 0)  k = j
            end do
            call sort8 (k,pgrp(1,it))
            if (use_thole) then
               write (ikey,200)  it,polarity(i),thole(i),
     &                           (pgrp(j,it),j=1,k)
  200          format ('polarize',7x,i5,5x,2f11.4,2x,20i5)
            else if (use_dirdamp) then
               write (ikey,205)  it,polarity(i),thole(i),
     &                           dirdamp(i),(pgrp(j,it),j=1,k)
  205          format ('polarize',7x,i5,5x,3f11.4,2x,20i5)
            else if (use_chgpen) then
               write (ikey,210)  it,polarity(i),(pgrp(j,it),j=1,k)
  210          format ('polarize',7x,i5,5x,f11.4,6x,20i7)
            end if
         end if
         tmax = max(it,tmax)
      end do
      close (unit=ikey)
      return
      end
