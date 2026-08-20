import React, {useState} from 'react';
import {
  View, Text, StyleSheet, FlatList,
  TextInput, TouchableOpacity, SafeAreaView,
} from 'react-native';
import ChatCard from '../components/ChatCard';

const CHATS = [
  {
    id: '1', name: 'Rashi ❤️', lastMessage: 'Miss you so much 🥺',
    time: '2m', unread: 3, isOnline: true, avatar: 'R',
  },
  {
    id: '2', name: 'Rashi (Work)', lastMessage: 'Did you get my file?',
    time: '1h', unread: 0, isOnline: false, avatar: 'R',
  },
  {
    id: '3', name: 'Our Memories', lastMessage: 'Added a new photo 📸',
    time: '3h', unread: 1, isOnline: false, avatar: 'M',
  },
];

export default function ChatListScreen({navigation}: any) {
  const [search, setSearch] = useState('');
  const filtered = CHATS.filter(c =>
    c.name.toLowerCase().includes(search.toLowerCase()),
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Messages</Text>
        <TouchableOpacity style={styles.newBtn}>
          <Text style={styles.newBtnText}>+</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.searchWrap}>
        <Text style={styles.searchIcon}>🔍</Text>
        <TextInput
          style={styles.search}
          placeholder="Search conversations..."
          placeholderTextColor="#3D5A80"
          value={search}
          onChangeText={setSearch}
        />
      </View>

      <FlatList
        data={filtered}
        keyExtractor={item => item.id}
        renderItem={({item}) => (
          <ChatCard
            chat={item}
            onPress={() =>
              navigation.navigate('Chat', {
                chatId: item.id,
                name: item.name,
                isOnline: item.isOnline,
              })
            }
          />
        )}
        ItemSeparatorComponent={() => <View style={styles.separator} />}
        contentContainerStyle={styles.list}
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, backgroundColor: '#0B1120'},
  header: {
    flexDirection: 'row', justifyContent: 'space-between',
    alignItems: 'center', paddingHorizontal: 20, paddingTop: 16, paddingBottom: 8,
  },
  title: {color: 'white', fontSize: 28, fontWeight: '800', letterSpacing: -0.5},
  newBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: '#4F8CFF', justifyContent: 'center', alignItems: 'center',
  },
  newBtnText: {color: 'white', fontSize: 22, fontWeight: '300', marginTop: -1},
  searchWrap: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: '#0F1C2E', marginHorizontal: 16, marginBottom: 8,
    borderRadius: 14, paddingHorizontal: 16, paddingVertical: 12,
    borderWidth: 0.5, borderColor: '#1E3A5F',
  },
  searchIcon: {fontSize: 16},
  search: {flex: 1, color: 'white', fontSize: 15},
  list: {paddingHorizontal: 16, paddingBottom: 20},
  separator: {height: 1, backgroundColor: '#0F1C2E', marginLeft: 72},
});