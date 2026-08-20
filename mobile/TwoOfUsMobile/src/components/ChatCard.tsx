import React from 'react';
import {View, Text, StyleSheet, TouchableOpacity} from 'react-native';

type Chat = {
  id: string;
  name: string;
  lastMessage: string;
  time: string;
  unread: number;
  isOnline: boolean;
  avatar: string;
};

type Props = {
  chat: Chat;
  onPress: () => void;
};

export default function ChatCard({chat, onPress}: Props) {
  return (
    <TouchableOpacity style={styles.card} onPress={onPress} activeOpacity={0.7}>
      <View style={styles.avatarWrap}>
        <View style={styles.avatar}>
          <Text style={styles.avatarText}>{chat.avatar}</Text>
        </View>
        {chat.isOnline && <View style={styles.onlineDot} />}
      </View>

      <View style={styles.info}>
        <View style={styles.topRow}>
          <Text style={styles.name} numberOfLines={1}>{chat.name}</Text>
          <Text style={styles.time}>{chat.time}</Text>
        </View>
        <View style={styles.bottomRow}>
          <Text style={styles.lastMsg} numberOfLines={1}>{chat.lastMessage}</Text>
          {chat.unread > 0 && (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{chat.unread}</Text>
            </View>
          )}
        </View>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 12, paddingHorizontal: 4, gap: 12,
  },
  avatarWrap: {position: 'relative'},
  avatar: {
    width: 50, height: 50, borderRadius: 25,
    backgroundColor: '#FF6B8A22', justifyContent: 'center', alignItems: 'center',
    borderWidth: 1.5, borderColor: '#FF6B8A44',
  },
  avatarText: {color: '#FF6B8A', fontWeight: '700', fontSize: 18},
  onlineDot: {
    position: 'absolute', bottom: 2, right: 2,
    width: 12, height: 12, borderRadius: 6,
    backgroundColor: '#1D9E75', borderWidth: 2, borderColor: '#0B1120',
  },
  info: {flex: 1},
  topRow: {
    flexDirection: 'row', justifyContent: 'space-between',
    alignItems: 'center', marginBottom: 4,
  },
  name: {color: 'white', fontWeight: '600', fontSize: 15, flex: 1, marginRight: 8},
  time: {color: '#3D5A80', fontSize: 12},
  bottomRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
  },
  lastMsg: {color: '#64748B', fontSize: 13, flex: 1, marginRight: 8},
  badge: {
    backgroundColor: '#4F8CFF', borderRadius: 10,
    minWidth: 20, height: 20, justifyContent: 'center', alignItems: 'center',
    paddingHorizontal: 5,
  },
  badgeText: {color: 'white', fontSize: 11, fontWeight: '700'},
});