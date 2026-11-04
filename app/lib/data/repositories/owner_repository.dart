const ownerLookupTimeout = Duration(seconds: 5);

class OwnershipRequest {
  const OwnershipRequest(
    this.placeId,
    this.status, {
    this.reason,
    this.revocationReason,
  });
  final String placeId;
  final String status;
  final String? reason, revocationReason;
}

abstract class OwnerRepository {
  Future<String?> ownerOf(String placeId);
  Future<List<OwnershipRequest>> requestsOf(String uid);
  Future<OwnershipRequest> request(String uid, String placeId);
}

const ownerContributionMessage =
    'Como titular verificado, você não pode avaliar, registrar visitas ou informar aberto/preço no próprio estabelecimento.';
