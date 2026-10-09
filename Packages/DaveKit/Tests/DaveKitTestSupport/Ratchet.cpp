#include "DaveKitTestSupport.h"
#include "../../Sources/CLibdave/libdave/cpp/src/mls_key_ratchet.h"

DAVEKeyRatchetHandle makeTestKeyRatchet(uint8_t epoch)
{
    auto suite = ::mlspp::CipherSuite(::mlspp::CipherSuite::ID::P256_AES128GCM_SHA256_P256);
    return reinterpret_cast<DAVEKeyRatchetHandle>(
      new discord::dave::MlsKeyRatchet(suite, ::mlspp::bytes_ns::bytes(32, epoch)));
}
