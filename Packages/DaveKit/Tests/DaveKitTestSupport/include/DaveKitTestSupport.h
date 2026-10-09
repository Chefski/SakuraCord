#pragma once
#include <dave/dave.h>
#ifdef __cplusplus
extern "C" {
#endif
DAVEKeyRatchetHandle makeTestKeyRatchet(uint8_t epoch);

typedef struct DaveTestExternalSender_s* DaveTestExternalSender;
typedef struct {
    const uint8_t* data;
    size_t count;
} DaveTestBytes;

// Returned bytes belong to the sender until its next operation.
DaveTestExternalSender makeTestExternalSender(void);
void destroyTestExternalSender(DaveTestExternalSender sender);
DaveTestBytes testExternalSenderPackage(DaveTestExternalSender sender);
DaveTestBytes testAddProposal(DaveTestExternalSender sender, uint64_t groupId,
                             const uint8_t* keyPackage, size_t count);
DaveTestBytes testCommitWelcomePart(DaveTestExternalSender sender,
                                   const uint8_t* combined, size_t count, bool welcome);
#ifdef __cplusplus
}
#endif
