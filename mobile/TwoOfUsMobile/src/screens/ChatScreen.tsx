import React, {useState, useRef} from 'react';
import {
  View, Text, TextInput, StyleSheet,
  FlatList, TouchableOpacity, SafeAreaView, KeyboardAvoidingView, Platform,
} from 'react-native';
import ChatBubble from '../components/ChatBubble';

type Message = {
  id: string;
  text: string;
  mine: boolean;
  time: string;
  read?: boolean;
};

const INITIAL: Message[] = [
  {id: '1', text: 'Hi ❤️', mine: false, time: '10:01 AM'},
  {id: '2', text: 'Hello! 😊', mine: true, time: '10:02 AM', read: true},
  {id: '3', text: 'How was your day?', mine: false, time: '10:03 AM'},
  {id: '4', text: 'Pretty good, had a productive session!', mine: true, time: '10:05 AM', read: true},
  {id: '5', text: 'Miss you 🥺', mine: false, time: '10:06 AM'},
];

export default function ChatScreen({route, navigation}: any) {
  const {name, isOnline} = route?.params ?? {name: 'Rashi ❤️', isOnline: true};
  const [messages, setMessages] = useState<Message[]>(INITIAL);
  const [text, setText] = useState('');
  const listRef = useRef<FlatList>(null);

  const sendMessage = () => {
    const trimmed = text.trim();
    if (!trimmed) return;
    const newMsg: Message = {
      id: Date.now().toString(),
      text: trimmed,
      mine: true,
      time: new Date().toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'}),
      read: false,
    };
    setMessages(prev => [...prev, newMsg]);
    setText('');
    setTimeout(() => listRef.current?.scrollToEnd({animated: true}), 100);
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.backBtn} onPress={() => navigation.goBack()}>
          <Text style={styles.backArrow}>←</Text>
        </TouchableOpacity>
        <View style={styles.headerInfo}>
          <View style={styles.headerAvatarWrap}>
            <View style={styles.headerAvatar}>
              <Text style={styles.headerAvatarText}>{name[0]}</Text>
            </View>
            {isOnline && <View style={styles.onlineDot} />}
          </View>
          <View>
            <Text style={styles.headerName}>{name}</Text>
            <Text style={styles.headerStatus}>{isOnline ? 'Online now' : 'Last seen recently'}</Text>
          </View>
        </View>
        <TouchableOpacity style={styles.menuBtn}>
          <Text style={styles.menuDots}>⋮</Text>
        </TouchableOpacity>
      </View>

      <KeyboardAvoidingView
        style={{flex: 1}}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        keyboardVerticalOffset={0}>
        <FlatList
          ref={listRef}
          data={messages}
          keyExtractor={item => item.id}
          renderItem={({item}) => (
            <ChatBubble
              text={item.text}
              mine={item.mine}
              time={item.time}
              read={item.read}
            />
          )}
          contentContainerStyle={styles.messageList}
          showsVerticalScrollIndicator={false}
          onContentSizeChange={() => listRef.current?.scrollToEnd({animated: false})}
        />

        <View style={styles.inputRow}>
          <TextInput
            style={styles.input}
            placeholder="Type something sweet..."
            placeholderTextColor="#3D5A80"
            value={text}
            onChangeText={setText}
            multiline
            onSubmitEditing={sendMessage}
          />
          <TouchableOpacity
            style={[styles.sendBtn, !text.trim() && styles.sendBtnDisabled]}
            onPress={sendMessage}
            activeOpacity={0.8}
            disabled={!text.trim()}>
            <Text style={styles.sendIcon}>↑</Text>
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, backgroundColor: '#0B1120'},
  header: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12,
    paddingVertical: 12, borderBottomWidth: 0.5, borderBottomColor: '#1E3A5F',
    backgroundColor: '#0B1120',
  },
  backBtn: {padding: 8},
  backArrow: {color: '#4F8CFF', fontSize: 20},
  headerInfo: {flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12},
  headerAvatarWrap: {position: 'relative'},
  headerAvatar: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: '#FF6B8A33', justifyContent: 'center', alignItems: 'center',
  },
  headerAvatarText: {color: '#FF6B8A', fontWeight: '700', fontSize: 16},
  onlineDot: {
    position: 'absolute', bottom: 1, right: 1,
    width: 10, height: 10, borderRadius: 5,
    backgroundColor: '#1D9E75', borderWidth: 2, borderColor: '#0B1120',
  },
  headerName: {color: 'white', fontWeight: '700', fontSize: 15},
  headerStatus: {color: '#1D9E75', fontSize: 11, marginTop: 1},
  menuBtn: {padding: 8},
  menuDots: {color: '#64748B', fontSize: 20},
  messageList: {padding: 16, paddingBottom: 8},
  inputRow: {
    flexDirection: 'row', alignItems: 'flex-end', gap: 10,
    paddingHorizontal: 14, paddingVertical: 12,
    borderTopWidth: 0.5, borderTopColor: '#1E3A5F',
    backgroundColor: '#0B1120',
  },
  input: {
    flex: 1, backgroundColor: '#0F1C2E', borderRadius: 22,
    paddingHorizontal: 18, paddingVertical: 12, color: 'white',
    fontSize: 15, maxHeight: 100, borderWidth: 0.5, borderColor: '#1E3A5F',
  },
  sendBtn: {
    width: 44, height: 44, borderRadius: 22,
    backgroundColor: '#4F8CFF', justifyContent: 'center', alignItems: 'center',
  },
  sendBtnDisabled: {backgroundColor: '#1E3A5F'},
  sendIcon: {color: 'white', fontSize: 18, fontWeight: '700'},
});