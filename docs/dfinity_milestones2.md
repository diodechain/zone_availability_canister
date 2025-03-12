# Sprint Goals for First 14 days / Milestone #1/5

## Story

The first milestone is focused on research and design around vetKEYs ([vetKEYs Overview](https://internetcomputer.org/docs/current/references/vetkeys-overview)) to establish key exchanges and storage access semantics for Teams working on shared storage within the Diode Collab app.

During this phase, we will categorize different use cases and their demands on privacy and access controls, which include:
- Chat attachments
- Shared documents, notes, and other files
- Zone & Team metadata (e.g., profile pictures, alias names, personal info)
- Role based access (Admin, Owner, Moderator, Member, ReadOnly, etc.)
- Large files (e.g., videos, images, audio)

## Deliverables
- **Design Document**: Architecture of Zone Canister usage of vetKEYs
- **Use Case Documentation**: Mapping use case features to technical specifications
- **Demo Recording**: Explanation of designs and key decisions

## Sprint (Days 1-14)
- Research existing vetKEYs implementation and access control models
- Develop architectural blueprints and storage security models
- Identify potential bottlenecks and challenges in implementation
- Prepare documentation and present findings

---

# Milestone #2/5 – Initial Implementation of Zone Canister Storage with Basic Metadata and Encryption Stubs

## Story

This milestone focuses on the initial technical implementation of Zone Canister storage for encrypted data exchange using vetKEY encryption stubs. During this phase, the Zone Canister will support "zone public" small metadata (such as zone name, zone logo, etc.) encrypted by a "zone shared" key. A later milestone will include transitioning to the full encryption implementation and measuring cost/performance impact.

## Deliverables
- **Initial Canister Contract**: Implemented and deployable with metadata handling and encryption stubs
- **Unit Tests & Benchmarks**: Validating metadata encryption, storage, and retrieval
- **Encryption & Cost Research Report**: Addressing current state of vetKEY encryption and learnings
- **Demo Recording**: Canister deployment and basic operations

## Sprint 1 (Days 15-24): Core Storage Implementation with Metadata Handling
- Develop core canister logic and key validation functions
- Implement encryption stubs for metadata handling
- Research cost implications of encryption in canisters

## Sprint 2 (Days 25-34): Encryption Research & Optimization Strategies
- Conduct benchmark tests for metadata storage
- Define optimization policies (e.g., chunk sizes, update-limits)
- Document potential cost mitigation strategies

## Sprint 3 (Days 35-44): Testing & Performance Validation
- Test metadata upload and retrieval performance
- Benchmark storage efficiency and scalability
- Finalize implementation and documentation

---

# Milestone #3/5 – Handling Encrypted Chat Attachments

## Story

This milestone extends the Zone Canister to handle already encrypted chat attachments. This implementation ensures that attachments are securely stored and retrievable while maintaining encryption integrity.

## Deliverables
- **Attachment Storage Implementation**: Secure storage of encrypted files
- **Unit Tests & Performance Metrics**: Attachment retrieval benchmarks
- **Demo Recording**: Showing attachment storage and retrieval in action

## Sprint 1 (Days 45-54): Implementation of Secure Attachment Storage
- Define storage structure for encrypted attachments
- Implement attachment validation and metadata handling
- Research cost impact of storing encrypted attachments

## Sprint 2 (Days 55-64): Scalability & Cost Benchmarking
- Benchmark attachment storage efficiency
- Define policies for large attachments and auto-pruning
- Implement performance optimizations

## Sprint 3 (Days 65-74): Testing & Finalization
- Conduct security and access validation
- Optimize retrieval speed for encrypted files
- Finalize documentation and prepare for integration

---

# Milestone #4/5 – Full vetKEY Integration & Large Data Handling Policies

## Story

This milestone ensures that the Zone Canister handles all shared and privately shared data with proper vetKEY encryption while implementing policies for handling large files efficiently.

## Deliverables
- **Full vetKEY Integration**: All shared data is encrypted using vetKEYs
- **Scalability Optimization Policies**: Implemented strategies for large data handling
- **Demo Recording**: Showcasing secure data sharing and pruning policies

## Sprint 1 (Days 75-84): Final Encryption Implementation
- Transition from encryption stubs to full vetKEY encryption
- Implement encryption handling for shared/private data
- Benchmark encryption cost

## Sprint 2 (Days 85-94): Large Data Handling & Cost Optimization
- Implement policies for large file warnings and automatic pruning
- Research and optimize data storage costs
- Test retrieval efficiency for large-scale data

## Sprint 3 (Days 95-104): Security & Performance Validation
- Validate encryption integrity and access control
- Optimize performance for large-scale file sharing
- Finalize documentation and demo preparations

---

# Milestone #5/5 – App Integration & Production Launch

## Story

The final milestone ensures that all features are integrated into the Diode Collab app, optimized for production deployment, and launched with a staged rollout.

## Deliverables
- **Production-Ready Release**: Final canister and app integration
- **Automated Monitoring**: Performance metrics and security logging
- **Cost Mitigation Strategies**: Finalized policies for storage and processing efficiency
- **Final Demo Recording**: Showcasing the complete functionality

## Sprint 1 (Days 105-114): Full App Integration
- Implement UI components for seamless user interaction
- Finalize API integration with storage mechanisms
- Ensure smooth user experience for file uploads/downloads

## Sprint 2 (Days 115-124): Deployment Preparation & Scalability Validation
- Deploy system monitoring and logging tools
- Final testing on cost-efficient operations
- Ensure compliance with scalability best practices

## Sprint 3 (Days 125-134): Staged Rollout & Monitoring
- Perform a staged rollout and monitor adoption
- Implement alerts and fail-safe mechanisms for cost control
- Finalize documentation and support materials

---

This plan ensures a structured progression from research to deployment while incorporating incremental feature deliveries in milestones 2-5. The phased integration of vetKEY encryption allows for flexibility while ensuring performance and cost optimizations.
