import 'package:cloud_firestore/cloud_firestore.dart';

/// Day 1: stub only. Collections get populated starting Day 2
/// (documents), Day 4 (users/roles, knowledge graph nodes/edges),
/// and Day 5-6 (knowledge cards, incidents, compliance flags).
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get users => _db.collection('users');
  CollectionReference get documents => _db.collection('documents');
  CollectionReference get equipment => _db.collection('equipment');
  CollectionReference get knowledgeCards => _db.collection('knowledge_cards');
  CollectionReference get incidents => _db.collection('incidents');
  CollectionReference get complianceFlags => _db.collection('compliance_flags');
  CollectionReference get graphEdges => _db.collection('graph_edges');
}
