#ifndef _EVENT_SEQ_INCLUDED_
#define _EVENT_SEQ_INCLUDED_
#include <map>
#include <R.h>
#include <Rinternals.h>
#include "eventdictionary.h"
//using namespace std;
//D�claration des types (d�finitions ci-apr�s)
class SequenceEventNode;
class Sequence;
//Global variable, check for correct type
//static SEXP TMRSEQUENCE_type_tag;
#define TMRSEQUENCE_type_tag R_NilValue

#define TMR_STRING_BUFFER_SIZE 2048

///Macro checking for type

#define CHECK_TMRSEQ_TYPE(s) do { \
    if (TYPEOF(s) != EXTPTRSXP || \
            R_ExternalPtrTag(s) != TMRSEQUENCE_type_tag) \
        error("bad sequence format"); \
} while (0)

///Checking and cast for Sequence type

    #define ASSIGN_TMRSEQ_TYPE(seq,ptr) do { \
        if (TYPEOF(ptr) != EXTPTRSXP || \
                R_ExternalPtrTag(ptr) != TMRSEQUENCE_type_tag) \
            error("bad sequence format"); \
        seq= static_cast<Sequence *>(R_ExternalPtrAddr(ptr));\
    } while (0)


        /** Sequence finalizer, used by R to free memory
        */
        void finalizeSequence(SEXP ptr);

inline SEXP makeTMRSequence(Sequence *s, SEXP cl) {
    SEXP tmpseq;
    tmpseq = R_MakeExternalPtr(s, TMRSEQUENCE_type_tag, R_NilValue);
    R_RegisterCFinalizerEx(tmpseq, (R_CFinalizer_t) finalizeSequence, TRUE);
    classgets(tmpseq, cl);
    return tmpseq;
}


/**
  Contain one event in a sequence (individual or a generic subsequence),
  reponsible for deleting next event in sequence
  So events should never be shared between sequences
*/
class SequenceEventNode {
    //Protected, May be used by subclass
protected:
    ///type of the event should be positive
    int type;
    ///Next node in sequence, may be null
    SequenceEventNode * next;
    ///timegap with previous event, may be 0 for simulateneity, should never be negative
    double gap;
public:
    ///Ctor
    ///t: type
    ///g: gap with previous node
    SequenceEventNode(const int& t, const double& g) {
        this->type=t;
        this->gap=g;
        this->next=NULL;
    }
    ///Dtor, delete remaining events in sequences
    virtual ~SequenceEventNode() {
        if (next)delete next;
    }
    ///Next event in chain
    inline SequenceEventNode * getNext() {
        return this->next;
    }
    ///Next event in chain Setter
    inline void setNext(SequenceEventNode * s) {
        this->next=s;
    }
    ///true if has next event
    inline bool hasNext() {
        return this->next!=NULL;
    }
    ///Return gap with previous event in sequence
    inline const double& getGap() {
        return this->gap;
    }
    ///Type of this event
    inline const int& getType() {
        return this->type;
    }
    ///Set next event, should be avoided
    /*void setNext(SequenceEventNode* n) {
        this->next=n;
    }*/
    ///Print a representation on R console
    //virtual void print(const bool& start);
    ///Print a representation on a given string
    ///Return the number of char used
    virtual int sprint(char * buffer, int index, const bool& start, const bool &printGap, const EventDictionary& ed, const double & remainingTime);
    ///Add an event at the end of the event chain
    void addEvent(const int &e,const double &t);

    //Subsequence functions
    ///Count the number time we found this sequence in s
    int count(SequenceEventNode * s, const double &maxGap, const double& windowSize, const double & ageMaxEnd, const double& gapConsumed, const double& currentAge);
    ///Check if this can be considered equal to s
    inline bool checkTypeGap(SequenceEventNode * s,const double& passedGap) {
        return this->type==s->type&&((this->gap>0&&passedGap>0)||(this->gap==0&&passedGap==0));
    }
    inline bool checkType(SequenceEventNode * s) {
        return this->type==s->type;
    }
    inline bool lessThan(const int & e, const double& g){
		if(this->gap<g) return true;
		else if(this->gap==g&&this->type<e)return true;
		else return false;
    }
    inline bool greaterThan(const int & e, const double& g){
		if(this->gap>g) return true;
		else if(this->gap==g&&this->type>e)return true;
		else return false;
    }
    ///Give a deep copy of this subsequence
    SequenceEventNode * copy();


};
///Represent an individual sequence
class Sequence {

public:
    ///CTor
    ///The id is used in file format and to compute support in prefix tree
    Sequence(const int&id, EventDictionary* ed);
    ///Dtor, delete all events
    virtual ~Sequence();
    ///Return idpers (unique)
    const int& getIDpers() {
        return this->idpers;
    }
    ///Print event chain
    void print();
    ///Print event chain on a string buffer
    int sprint(char * buffer);
    ///Return true, if generic subsequence
    bool isGeneric() {
        return this->idpers==-1;
    }
    ///if false, this is the empty sequence. Should be avoided
    bool hasEvent() {
        return this->event!=NULL;
    }
    ///Get the event of this sequence
    SequenceEventNode * getEvent() {
        return this->event;
    }
    ///Add an event to this sequence (used to build sequences)
    void addEvent(const int &eventType,const double &t);
    ///Count the number time we found this sequence in s
    int count(Sequence * s, const double &maxGap, const double& windowSize, const double & ageMin, const double & ageMax, const double & ageMaxEnd);
    ///Return age of first occurence of this sequence in sequence s
    double first_occurence(Sequence * s, const double &maxGap, const double& windowSize, const double & ageMin, const double & ageMax, const double & ageMaxEnd);
    ///Give a deep copy of this subsequence
    Sequence * copy();
    EventDictionary * getDictionary(){return this->dict;}
    double getObsTime(){return this->obsTime;}
    void setObsTime(const double &t){this->obsTime=t;}
    bool contain(const EventSet& es, const bool &exclude);
    //bool notContain(const EventSet& es);
private:
    ///Unique ID, may be -1 for generic subsequences
    int idpers;
    ///First event in sequence
    SequenceEventNode *event;
    //Dictionnary to use
    //Ref counted
    EventDictionary * dict;
    double obsTime;

};

#endif