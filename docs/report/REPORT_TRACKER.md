# WS-INT8 Systolic Array for Neural Network Inference
## College Report Tracker

> Master checklist for report preparation.
> Update this file as each project milestone is completed.
> Do not mark an item complete without corresponding evidence.

---

# Preliminary Pages

- [ ] Title Page
- [ ] University Certificate
- [ ] Industry Certificate
- [ ] Acknowledgement
- [ ] Company Profile
- [ ] Synopsis / Abstract
- [ ] Table of Contents
- [ ] List of Figures
- [ ] List of Tables

---

# Chapter 1 — Problem Definition & Design Specifications

## Content
- [ ] Problem Definition
- [ ] Motivation
- [ ] Objectives
- [ ] Scope
- [ ] Design Specifications
- [ ] System Requirements

## Figures
- [ ] System-level architecture
- [ ] Design/dataflow overview

## Tables
- [ ] Design parameters
- [ ] Interface/specification table

---

# Chapter 2 — Basic Theory

## Content
- [ ] Neural Network Inference
- [ ] MAC Operation
- [ ] INT8 Quantization
- [ ] Systolic Array
- [ ] Weight-Stationary Dataflow
- [ ] Processing Element
- [ ] Partial-Sum Accumulation
- [ ] Overflow Considerations

## Figures
- [ ] MAC concept
- [ ] Weight-stationary dataflow
- [ ] Systolic-array concept
- [ ] PE concept

---

# Chapter 3 — Design

## Processing Element
- [ ] PE architecture
- [ ] PE datapath
- [ ] PE interface
- [ ] PE control
- [ ] Accumulator
- [ ] Overflow detection

## PE Row
- [ ] PE-row architecture
- [ ] Activation broadcast
- [ ] Weight distribution
- [ ] Partial-sum propagation
- [ ] Parameterization

## 2D Systolic Array
- [ ] Array architecture
- [ ] Data movement
- [ ] Weight-stationary mapping
- [ ] Control / timing

---

# Chapter 4 — Implementation & Testing

## RTL Implementation
- [ ] PE RTL
- [ ] PE-row RTL
- [ ] 2D-array RTL

## Verification Methodology
- [ ] Testbench architecture
- [ ] Directed tests
- [ ] Self-checking tests
- [ ] Boundary testing
- [ ] Reset testing
- [ ] Timing verification
- [ ] Overflow verification

## PE Verification
- [ ] Basic correctness
- [ ] Zero case
- [ ] Weight reuse
- [ ] Positive boundary
- [ ] Signed overflow
- [ ] Signed underflow
- [ ] Mid-stream reset

## PE Row Verification
- [ ] Basic correctness
- [ ] Weight reload
- [ ] Boundary / overflow
- [ ] Mid-stream reset
- [ ] Cycle-level timing
- [ ] Regression result

## Implementation Results
- [ ] Simulation results
- [ ] Lint results
- [ ] Synthesis results
- [ ] Area
- [ ] Power
- [ ] Timing
- [ ] PPA analysis

---

# Conclusion

- [ ] Achievements
- [ ] Quantitative results
- [ ] Limitations
- [ ] Future Work

---

# References

- [ ] Academic papers
- [ ] Books
- [ ] Datasheets / technical documentation
- [ ] Tools / documentation

---

# Appendix

- [ ] RTL source
- [ ] Testbench source
- [ ] Additional verification evidence
- [ ] Additional tables
