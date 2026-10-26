#include "DaveKitTestSupport.h"
#include "../../Sources/CLibdave/libdave/cpp/src/mls/parameters.h"
#include "../../Sources/CLibdave/libdave/cpp/src/mls/util.h"

// The external-sender wire construction follows discord/libdave v1.2.1/cpp's
// test/external_sender.cpp. Sessions and cryptography use the production code.
struct DaveTestExternalSender_s {
    ::mlspp::CipherSuite suite = discord::dave::mls::CiphersuiteForProtocolVersion(1);
    ::mlspp::SignaturePrivateKey key = ::mlspp::SignaturePrivateKey::generate(suite);
    ::mlspp::ExternalSender sender{key.public_key,
                                 ::mlspp::Credential::basic({0x00, 0x01, 0x01, 0x00})};
    std::vector<uint8_t> buffer;

    DaveTestBytes store(std::vector<uint8_t> bytes)
    {
        buffer = std::move(bytes);
        return {buffer.data(), buffer.size()};
    }
};

DaveTestExternalSender makeTestExternalSender(void)
{
    try {
        return new DaveTestExternalSender_s();
    }
    catch (...) {
        return nullptr;
    }
}

void destroyTestExternalSender(DaveTestExternalSender sender)
{
    delete sender;
}

DaveTestBytes testExternalSenderPackage(DaveTestExternalSender sender)
{
    if (!sender) return {};
    try {
        return sender->store(::mlspp::tls::marshal(sender->sender));
    }
    catch (...) {
        return {};
    }
}

DaveTestBytes testAddProposal(DaveTestExternalSender sender, uint64_t groupId,
                             const uint8_t* keyPackage, size_t count)
{
    if (!sender || !keyPackage) return {};
    try {
        auto bytes = ::mlspp::bytes_ns::bytes(std::vector<uint8_t>(keyPackage, keyPackage + count));
        auto proposal = ::mlspp::Proposal{::mlspp::Add{{::mlspp::tls::get<::mlspp::KeyPackage>(bytes)}}};
        auto message = ::mlspp::external_proposal(sender->suite,
          discord::dave::mls::BigEndianBytesFrom(groupId), 0, proposal, 0, sender->key);
        ::mlspp::tls::ostream out;
        out << false; // Append proposals, rather than revoke them.
        out << std::vector<::mlspp::MLSMessage>{message};
        return sender->store(out.bytes());
    }
    catch (...) {
        return {};
    }
}

DaveTestBytes testCommitWelcomePart(DaveTestExternalSender sender,
                                   const uint8_t* combined, size_t count, bool welcome)
{
    if (!sender || !combined) return {};
    try {
        auto bytes = ::mlspp::bytes_ns::bytes(std::vector<uint8_t>(combined, combined + count));
        ::mlspp::tls::istream in(bytes);
        ::mlspp::MLSMessage commit;
        ::mlspp::Welcome joined;
        in >> commit;
        in >> joined;
        return sender->store(welcome ? ::mlspp::tls::marshal(joined) : ::mlspp::tls::marshal(commit));
    }
    catch (...) {
        return {};
    }
}
