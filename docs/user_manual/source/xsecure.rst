.. _xsecure:

Xsecure extension
=================

.. note::

   Some Xsecure features have not been implemented yet.

|corev| has a custom extension called Xsecure, which encompass the following categories of security related features:

* Anti-tampering features

  * Protection against glitch attacks
  * Control flow integrity
  * Autonomous (hardware-based, low latency) response mechanisms

* Reduction of side channel leakage

.. _security_alerts:

Security alerts
---------------
|corev| has two alert outputs for signaling security issues: A major and a minor alert. The major alert (``alert_major_o``) indicates a critical security issue from which the core cannot recover. The minor alert (``alert_minor_o``) indicates potential security issues, which can be monitored by a system over time.
These outputs can be used by external hardware to trigger security incident responses like for example a system wide reset or a memory erase.
A security output is high for every clock cycle that the related security issue persists.

The following issues result in a major security alert:

* Register file ECC error
* Hardened PC error
* Hardened CSR error
* Interface integrity error

The following issues result in a minor security alert:

* LFSR0, LFSR1, LFSR2 lockup
* Instruction access fault
* Illegal instruction
* Load access fault
* Store/AMO access fault
* Instruction bus fault

Data independent timing
-----------------------
Data independent timing is enabled by setting the ``dataindtiming`` bit in the ``cpuctrl`` CSR.
This will make execution times of all instructions independent of the input data, making it more difficult for an external
observer to extract information by observing power consumption or exploiting timing side-channels.

When ``dataindtiming`` is set, the DIV, DIVU, REM and REMU instructions will have a fixed (data independent) latency and branches
will have a fixed latency as well, regardless of whether they are taken or not. See :ref:`pipeline-details` for details.

Note that the addresses used by loads and stores will still provide a timing side-channel due to the following properties:

* Misaligned loads and stores differ in cycle count from aligned loads and stores.
* Stores to a bufferable address range react differently to wait states than stores to a non-bufferable address range.

Similarly the target address of branches and jumps will still provide a timing side-channel due to the following property:

* Branches and jumps to non-word-aligned non-RV32C instructions differ in cycle count from other branches and jumps.

These timing side-channels can largely be mitigated by imposing (branch target and data) alignment restrictions on the used software.

Dummy instruction insertion
---------------------------

Dummy instructions are inserted at random intervals into the execution pipeline if enabled via the ``rnddummy`` bit in the ``cpuctrl`` CSR.
The dummy instructions have no functional impact on processor state, but add difficult-to-predict timing and power disruptions to the executed code.
This disruption makes it more difficult for an attacker to infer what is being executed, and also makes it more difficult to execute precisely timed fault injection attacks.

The frequency of injected instructions can be tuned via the ``rnddummyfreq`` bits in the ``cpuctrl`` CSR.

.. table:: Intervals for ``rnddummyfreq`` settings
  :name: Intervals for rnddummyfreq settings

  +------------------+----------------------------------------------------------+
  | ``rnddummyfreq`` | Interval                                                 |
  +------------------+----------------------------------------------------------+
  | 0000             | Dummy instruction every 1 - 4 real instructions          |
  +------------------+----------------------------------------------------------+
  | 0001             | Dummy instruction every 1 - 8 real instructions          |
  +------------------+----------------------------------------------------------+
  | 0011             | Dummy instruction every 1 - 16 real instructions         |
  +------------------+----------------------------------------------------------+
  | 0111             | Dummy instruction every 1 - 32 real instructions         |
  +------------------+----------------------------------------------------------+
  | 1111             | Dummy instruction every 1 - 64 real instructions         |
  +------------------+----------------------------------------------------------+

Other ``rnddummyfreq`` values are legal as well, but will have a less predictable performance impact.

The frequency of the dummy instruction insertion is randomized using an LFSR (LFSR0). The dummy instruction itself is also randomized based on LFSR0
and is constrained to ADD, MUL, AND and BLTU opcodes. The source data for the dummy instructions is obtained from LFSRs (LFSR1 and LFSR2) as opposed to sourcing
it from the register file.

The initial seed and output permutation for the LFSRs can be set using the following parameters from the |corev| top-level:

* ``LFSR0_CFG`` for LFSR0.
* ``LFSR1_CFG`` for LFSR1.
* ``LFSR2_CFG`` for LFSR2.

These parameters are of the type lfsr_cfg_t which has the following fields:


.. table:: LFSR Configuration Type
  :name: lfsr_cfg_t

  +------------------+-------------+---------------------------------------------------------------------------------+
  | **Field**        | **Type**    | **Description**                                                                 |
  +------------------+-------------+---------------------------------------------------------------------------------+
  | coeffs           | logic[31:0] | Coefficient controlling output permutation, must be non-zero                    |
  +------------------+-------------+---------------------------------------------------------------------------------+
  | default_seed     | logic[31:0] | Used as initial seed and for re-seeding in case of lockup, must be non-zero     |
  +------------------+-------------+---------------------------------------------------------------------------------+

Software can periodically re-seed the LFSRs with true random numbers (if available) via the ``secureseed*`` CSRs, making the insertion interval of
dummy instructions much harder to predict.

.. note::
  The user is recommended to pick maximum length LFSR configurations and must take care that writes to the ``secureseed*`` CSRs will not cause LFSR lockup.
  An LFSR lockup will result in a minor alert and will automatically cause a re-seed of the LFSR with the default seed from the related parameter.

.. note::
  Dummy instructions do affect the cycle count as visible via the ``mcycle`` CSR, but they are not counted as retired instructions (so they do not affect the ``minstret`` CSR).

Register file ECC
-----------------
ECC checking is added to all reads of the register file, where a checksum is stored for each register file word.
All 1-bit and 2-bit errors will be detected. This can be useful to detect fault injection attacks since the register file covers a reasonably large area of |corev|.
No attempt is made to correct detected errors, but a major alert is raised upon a detected error for the system to take action (see :ref:`security_alerts`).

.. note::
  This feature is logically redundant and might get partially or fully optimized away during synthesis.
  Special care might be needed and the final netlist must be checked to ensure that the ECC and correction logic is still present.
  A netlist test for this feature is recommended.

Hardened PC
-----------
During sequential execution the IF stage PC is hardened by checking that it has the correct value compared to the ID stage with an offset determined by the compressed/uncompressed state of the instruction in ID. 

In addition, the IF stage PC is checked for correctness for potential non-sequential execution due to control transfer instructions. For jumps (including mret) and branches, this is done by recomputing the PC target and branch decision (incurring an additional cycle for non-taken branches).

Any error in the check for correct PC or branch/jump decision will result in a pulse on the ``alert_major_o`` pin.

.. _hardened-csrs:

Hardened CSRs
-------------
Critical CSRs (``jvt``, ``mstatus``, ``mtvec``, ``pmpcfg``, ``pmpaddr*``, ``mseccfg*``, ``cpuctrl``, ``dcsr``, ``mie``, ``mepc``,
``mtvt``, ``mscratch``, ``mintstatus``, ``mintthresh``, ``mscratchcsw``, ``mscratchcswl`` and ``mclicbase``)
have extra glitch detection enabled.
For these registers a second copy of the register is added which stores a complemented version of the main CSR data. A constant check is made that the two copies are consistent, and a major alert is signaled if not (see :ref:`security_alerts`).

.. note::
  The shadow copies are logically redundant and are therefore likely to be optimized away during synthesis.
  Special care in the synthesis script is necessary (see :ref:`register-cells`) and the final netlist must be checked to ensure that the shadow copies are still present.
  A netlist test for this feature is recommended.

Functional unit and FSM hardening
---------------------------------
(Encode critical signals and FSM state such that certain glitch attacks can be detected)


.. _interface-integrity:

Interface integrity
-------------------

The OBI bus interfaces have associated parity and checksum signals:

* |corev| will generate odd parity signals ``instr_reqpar_o`` and ``data_reqpar_o`` for ``instr_req_o`` and ``data_req_o`` respectively.
* The environment is expected to drive ``instr_gntpar_i``, ``instr_rvalidpar_i``, ``data_gntpar_i`` and ``data_rvalidpar_i`` with odd parity for ``instr_gnt_i``, ``instr_rvalid_i``, ``data_gnt_i`` and ``data_rvalid_i`` respectively.
* |corev| will generate checksums ``instr_achk_o`` and ``data_achk_o`` for the instruction OBI interface and the data OBI interface respectively with checksums as defined in :numref:`Address phase checksum signal`.
* The environment is expected to drive ``instr_rchk_i`` and ``data_rchk_i`` for the instruction OBI interface and the data OBI interface respectively with checksums as defined in :numref:`Response phase checksum signal`.

.. table:: Address phase checksum signal
  :name: Address phase checksum signal

  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | **Signal**   | **Checksum computation**                        | **Comment**                                                                    |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[0]``  | Odd parity(``addr[7:0]``)                       |                                                                                |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[1]``  | Odd parity(``addr[15:8]``)                      |                                                                                |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[2]``  | Odd parity(``addr[23:16]``)                     |                                                                                |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[3]``  | Odd parity(``addr[31:24]``)                     |                                                                                |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[4]``  | Odd parity(``prot[2:0]``, ``memtype[1:0]``)     |                                                                                |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[5]``  | Odd parity(``be[3:0]``, ``we``)                 | For the instruction interface ``be[3:0]`` = 4'b1111 and ``we`` = 1'b0 is used. |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[6]``  | Odd parity(``dbg``)                             |                                                                                |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[7]``  | Odd parity(``atop``)                            | ``atop[5:0]`` = 6'b0 as the **A** extension is not implemented.                |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[8]``  | Odd parity(``wdata[7:0]``)                      | For the instruction interface ``wdata[7:0]`` = 8'b0.                           |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[9]``  | Odd parity(``wdata[15:8]``)                     | For the instruction interface ``wdata[15:8]`` = 8'b0.                          |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[10]`` | Odd parity(``wdata[23:16]``)                    | For the instruction interface ``wdata[23:16]`` = 8'b0.                         |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+
  | ``achk[11]`` | Odd parity(``wdata[31:24]``)                    | For the instruction interface ``wdata[31:24]`` = 8'b0.                         |
  +--------------+-------------------------------------------------+--------------------------------------------------------------------------------+

.. note::
   |corev| always generates its ``achk[11:8]`` bits dependent on ``wdata`` (even for read transactions). The ``achk[11:8]`` signal bits
   are however not required to be checked against ``wdata`` for read transactions (see [OPENHW-OBI]_). Whether the environment performs these checks or not
   is platform specific.

.. table:: Response phase checksum signal
  :name: Response phase checksum signal

  +--------------+-------------------------------------------------+--------------------------------------------------------------+
  | **Signal**   | **Checksum computation**                        | **Comment**                                                  |
  +--------------+-------------------------------------------------+--------------------------------------------------------------+
  | ``rchk[0]``  | Odd parity(``rdata[7:0]``)                      |                                                              |
  +--------------+-------------------------------------------------+--------------------------------------------------------------+
  | ``rchk[1]``  | Odd parity(``rdata[15:8]``)                     |                                                              |
  +--------------+-------------------------------------------------+--------------------------------------------------------------+
  | ``rchk[2]``  | Odd parity(``rdata[23:16]``)                    |                                                              |
  +--------------+-------------------------------------------------+--------------------------------------------------------------+
  | ``rchk[3]``  | Odd parity(``rdata[31:24]``)                    |                                                              |
  +--------------+-------------------------------------------------+--------------------------------------------------------------+
  | ``rchk[4]``  | Odd parity(``err``, ``exokay``)                 | ``exokay`` = 1'b0 as the **A** extension is not implemented. |
  +--------------+-------------------------------------------------+--------------------------------------------------------------+

.. note::
   |corev| always allows its ``rchk[3:0]`` bits to be dependent on ``rdata`` (even for write transactions). |corev| however only checks its ``rdata`` signal
   bits against ``rchk[3:0]`` for read transactions (see [OPENHW-OBI]_).

|corev| checks its OBI inputs against the related parity and checksum inputs (i.e. ``instr_gntpar_i``, ``data_gntpar_i``, ``instr_rvalidpar_i``, ``data_rvalidpar_i``, ``instr_rchk_i``
and ``data_rchk_i``) as specified in [OPENHW-OBI]_ and generates a pulse on the ``alert_major_o`` pin in cases of parity or checksum violations. The ``instr_rchk_i`` and ``data_rchk_i``
checks are only performed if so configured in the PMA (see :ref:`pma_integrity`).

The environment is expected to check the OBI outputs of |corev| against the related parity and checksum outputs (i.e. ``instr_reqpar_o``, ``data_reqpar_o``, ``instr_rchk_o`` and
``data_rchk_o``) as specified in [OPENHW-OBI]_. It is platform defined how the environment reacts in case of parity or checksum violations.

Bus interface hardening
-----------------------
Hardware checks are performed to check that the bus protocol is not being violated.

Reduction of profiling infrastructure
-------------------------------------
As **Zicntr** and **Zihpm** are not implemented user mode code does not have access to the Base Counters and Timers nor to the
Hardware Performance Counters. Furthermore the machine mode Hardware Performance Counters ``mhpmcounter3(h)`` - ``mhpmcounter31(h)``
and related event selector CSRs ``mhpmevent3`` - ``mhpmevent31`` are hard-wired to 0.
