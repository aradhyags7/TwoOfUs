import React, {useRef, useEffect} from 'react';
import {
  View, Text, StyleSheet, ScrollView,
  TouchableOpacity, Animated,
} from 'react-native';

const stats = [
  {label: 'Days Together', value: '247', icon: '🗓️'},
  {label: 'Messages', value: '4.2k', icon: '💬'},
  {label: 'Memories', value: '38', icon: '📸'},
];

const activity = [
  {text: 'Rashi sent you a voice note', time: '2m ago', dot: '#FF6B8A'},
  {text: 'You shared a memory', time: '1h ago', dot: '#4F8CFF'},
  {text: 'New photo added to gallery', time: '3h ago', dot: '#1D9E75'},
];

export default function HomeScreen({navigation}: any) {
  const fadeAnim = useRef(new Animated.Value(0)).current;
  const slideAnim = useRef(new Animated.Value(20)).current;

  useEffect(() => {
    Animated.parallel([
      Animated.timing(fadeAnim, {toValue: 1, duration: 600, useNativeDriver: true}),
      Animated.timing(slideAnim, {toValue: 0, duration: 600, useNativeDriver: true}),
    ]).start();
  }, []);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
      <Animated.View style={{opacity: fadeAnim, transform: [{translateY: slideAnim}]}}>

        <View style={styles.header}>
          <View>
            <Text style={styles.greeting}>Good evening 🌙</Text>
            <Text style={styles.name}>Aradhya</Text>
          </View>
          <TouchableOpacity style={styles.avatar}>
            <Text style={styles.avatarText}>A</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.heroCard}>
          <Text style={styles.heroHeart}>♥</Text>
          <Text style={styles.heroTitle}>TwoOfUs</Text>
          <Text style={styles.heroBadge}>Private & Secure</Text>
        </View>

        <Text style={styles.sectionLabel}>Your story</Text>
        <View style={styles.statsRow}>
          {stats.map(s => (
            <View key={s.label} style={styles.statCard}>
              <Text style={styles.statIcon}>{s.icon}</Text>
              <Text style={styles.statValue}>{s.value}</Text>
              <Text style={styles.statLabel}>{s.label}</Text>
            </View>
          ))}
        </View>

        <Text style={styles.sectionLabel}>Recent activity</Text>
        <View style={styles.activityCard}>
          {activity.map((a, i) => (
            <View key={i} style={[styles.activityRow, i < activity.length - 1 && styles.activityBorder]}>
              <View style={[styles.activityDot, {backgroundColor: a.dot}]} />
              <View style={{flex: 1}}>
                <Text style={styles.activityText}>{a.text}</Text>
                <Text style={styles.activityTime}>{a.time}</Text>
              </View>
            </View>
          ))}
        </View>

        <TouchableOpacity
          style={styles.chatButton}
          onPress={() => navigation.navigate('Chats')}
          activeOpacity={0.85}>
          <Text style={styles.chatButtonText}>Go to Chats →</Text>
        </TouchableOpacity>

      </Animated.View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, backgroundColor: '#0B1120'},
  scroll: {padding: 24, paddingTop: 56, paddingBottom: 40},
  header: {
    flexDirection: 'row', justifyContent: 'space-between',
    alignItems: 'center', marginBottom: 28,
  },
  greeting: {color: '#64748B', fontSize: 14},
  name: {color: 'white', fontSize: 24, fontWeight: '700'},
  avatar: {
    width: 44, height: 44, borderRadius: 22,
    backgroundColor: '#4F8CFF', justifyContent: 'center', alignItems: 'center',
  },
  avatarText: {color: 'white', fontWeight: '700', fontSize: 16},
  heroCard: {
    backgroundColor: '#0F1C2E',
    borderRadius: 24, padding: 28, alignItems: 'center',
    marginBottom: 28, borderWidth: 0.5, borderColor: '#1E3A5F',
  },
  heroHeart: {fontSize: 36, color: '#FF6B8A', marginBottom: 8},
  heroTitle: {
    color: 'white', fontSize: 32, fontWeight: '800',
    letterSpacing: -0.5, marginBottom: 10,
  },
  heroBadge: {
    color: '#4F8CFF', fontSize: 12, fontWeight: '600',
    backgroundColor: '#0A1A33', paddingHorizontal: 14,
    paddingVertical: 6, borderRadius: 20, letterSpacing: 0.5,
    borderWidth: 0.5, borderColor: '#1E3A5F',
  },
  sectionLabel: {
    color: '#64748B', fontSize: 12, fontWeight: '600',
    letterSpacing: 1, marginBottom: 12, textTransform: 'uppercase',
  },
  statsRow: {flexDirection: 'row', gap: 10, marginBottom: 28},
  statCard: {
    flex: 1, backgroundColor: '#0F1C2E', borderRadius: 18,
    padding: 16, alignItems: 'center', borderWidth: 0.5, borderColor: '#1E3A5F',
  },
  statIcon: {fontSize: 20, marginBottom: 6},
  statValue: {color: 'white', fontSize: 20, fontWeight: '700'},
  statLabel: {color: '#64748B', fontSize: 10, marginTop: 2, textAlign: 'center'},
  activityCard: {
    backgroundColor: '#0F1C2E', borderRadius: 20,
    padding: 4, borderWidth: 0.5, borderColor: '#1E3A5F', marginBottom: 28,
  },
  activityRow: {flexDirection: 'row', alignItems: 'center', padding: 14, gap: 12},
  activityBorder: {borderBottomWidth: 0.5, borderBottomColor: '#1E2D42'},
  activityDot: {width: 8, height: 8, borderRadius: 4},
  activityText: {color: 'white', fontSize: 13, fontWeight: '500'},
  activityTime: {color: '#64748B', fontSize: 11, marginTop: 2},
  chatButton: {
    backgroundColor: '#4F8CFF', borderRadius: 16,
    padding: 17, alignItems: 'center',
  },
  chatButtonText: {color: 'white', fontWeight: '700', fontSize: 16},
});