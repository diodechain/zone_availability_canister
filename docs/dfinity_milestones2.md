# Sprint Goals for First 14 days / Milestone #1/5

## Story

The first milestone is focused on research and design around vetKEYs ([vetKEYs Overview](https://internetcomputer.org/docs/current/references/vetkeys-overview)) to establish key exchanges and storage access semantics for Teams working on shared storage within the Diode Collab app.

During this phase, we will categorize different use cases and their demands on privacy and access controls, which include:
- Shared notes
- Shared files
- Zone & Team metadata (e.g., profile pictures, alias names, personal info)
- Zone Bookmarks
- Zone Data share links
- Zone internal permission roles (Admin, Owner, Moderator, Member, ReadOnly, etc.)
- Zone devices and their access permissions

## Deliverables
- **Design Document**: Architecture of Zone Canister usage of vetKEYs
- **Use Case Documentation**: Mapping use case features to technical specifications
- **Demo Recording**: Explanation of designs and key decisions
- **Interaction**

## Sprint (Days 1-14)
- Research existing vetKEYs implementation and access control models
- Develop architectural blueprints and storage security models
- Identify potential bottlenecks and challenges in implementation
- Prepare documentation and present findings

---

# Milestone #2/5 – Initial Implementation of Zone Canister Storage with vetKEY Stubs

## Story

This milestone focuses on the initial technical implementation of Zone Canister storage for encrypted data exchange using vetKEY encryption stubs. Since the availability of the full vetKEY encryption may be uncertain during this timeframe, this phase will use stubs to proceed with development. A later milestone will include transitioning to the real encryption implementation and measuring cost/performance impact. Additionally, we will research the scalability and cost concerns of ICP canister storage for large files.

## Deliverables
- **Initial Canister Contract**: Implemented and deployable with encryption stubs
- **Unit Tests & Benchmarks**: Validating encryption stubs, storage, and retrieval
- **Scalability & Cost Research Report**: Addressing large file storage concerns
- **Demo Recording**: Canister deployment and basic operations

## Sprint 1 (Days 15-24): Core Storage Implementation with vetKEY Stubs
- Develop core canister logic and key validation functions
- Implement encryption stubs for future vetKEY integration
- Research cost implications of encryption in canisters

## Sprint 2 (Days 25-34): Scalability Research & Optimization Strategies
- Conduct benchmark tests for large file storage
- Define optimization policies (e.g., chunk sizes, file size limits, auto-pruning, warnings, subnet sharding)
- Document potential cost mitigation strategies

## Sprint 3 (Days 35-44): Testing & Performance Validation
- Test data upload and retrieval performance
- Benchmark storage efficiency and scalability
- Finalize implementation and documentation

---

# Milestone #3/5 – Authorization & Access Control Integration

## Story

In this milestone, we integrate authentication and authorization mechanisms to ensure secure access to the Zone Canister storage. Additionally, we analyze the cost implications of permission checks and authentication mechanisms within canisters.

## Deliverables
- **Authentication Logic**: Implementation of vetKEYs-based authentication
- **Access Control Functions**: User-based permission enforcement
- **Cost Analysis Report**: Evaluating the efficiency of authentication mechanisms
- **Demo Recording**: Showcasing access control scenarios

## Sprint 1 (Days 45-54): Authentication Workflow Development
- Develop and test authentication workflows
- Implement role-based permission logic
- Research cost implications of authentication operations

## Sprint 2 (Days 55-64): Scalability & Cost Benchmarking
- Benchmark authentication logic performance
- Optimize and refine access control mechanisms
- Implement monitoring for excessive costs due to access validation

## Sprint 3 (Days 65-74): Testing & Finalization
- Conduct security tests and optimizations
- Validate authentication and prevent unauthorized access
- Finalize documentation and prepare for integration

---

# Milestone #4/5 – Full Integration with Diode Collab UI

## Story

This milestone focuses on integrating the developed canister storage and access control logic into the Diode Collab app’s UI while ensuring cost-efficient and scalable data handling.

## Deliverables
- **Updated UI/UX**: Diode Collab App integrated with canister storage
- **Performance & Stress Testing**: Validation under real-world conditions
- **Scalability Optimization Policies**: Defining strategies for data lifecycle management
- **Demo Recording**: End-to-end user experience walkthrough

## Sprint 1 (Days 75-84): UI Implementation & API Integration
- Implement UI components for managing and accessing storage
- Develop API endpoints for seamless interaction with canisters
- Research impact of frequent UI requests on canister cycles

## Sprint 2 (Days 85-94): Optimization & Load Testing
- Optimize data storage and retrieval for large-scale usage
- Implement auto-pruning strategies for cost control
- Conduct UI/UX testing with user feedback incorporation

## Sprint 3 (Days 95-104): Security & Cost Management Finalization
- Finalize security mechanisms within the UI
- Implement alerts for large file uploads and cost monitoring
- Document best practices for efficient storage utilization

---

# Milestone #5/5 – Final Optimization & Deployment with Full vetKEY Integration

## Story

The final milestone ensures that all features are optimized for production deployment. This includes transitioning from vetKEY encryption stubs to the full encryption implementation, measuring its cost/performance impact, and finalizing security and scalability enhancements.

## Deliverables
- **Production-Ready Release**: Final canister and app integration with full vetKEY encryption
- **Monitoring Dashboard**: Performance metrics and security logging
- **Cost Mitigation Strategies**: Finalized policies for storage and processing efficiency
- **Final Demo Recording**: Showcasing the complete functionality

## Sprint 1 (Days 105-114): Full vetKEY Encryption Integration
- Replace encryption stubs with real vetKEY encryption
- Conduct encryption cost and performance benchmarking
- Optimize storage efficiency based on findings

## Sprint 2 (Days 115-124): Deployment Preparation & Scalability Validation
- Deploy system monitoring and logging tools
- Final testing on cost-efficient operations
- Ensure compliance with scalability best practices

## Sprint 3 (Days 125-134): Staged Rollout & Monitoring
- Perform a staged rollout and monitor adoption
- Implement alerts and fail-safe mechanisms for cost control
- Finalize documentation and support materials

---

This plan ensures a structured progression from research to deployment while incorporating critical considerations for scalability and cost management at each stage. The phased integration of vetKEY encryption allows for flexibility while ensuring performance and cost optimizations.
