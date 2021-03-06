/*
    File: exhaustiveSearchOneSequence.h
*/

/*
Copyright (c) 2014, Christian E. Schafmeister
 
CLASP is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
 
See directory 'clasp/licenses' for full details.
 
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
/* -^- */
       
       
#ifndef	ExhaustiveSearchOneSequence_H //[
#define ExhaustiveSearchOneSequence_H



#include <stdio.h>
#include <string>
#include <vector>
#include <set>
#include "foundation.h"
#include "object.h"
#include "search.h"
#include "numerics.h"


namespace mbb {



SMART(ScorerStatistics);
SMART(ExhaustiveSearchOneSequence);
__BEGIN_CLASS_DEFINITION(MbbPackage,O_ExhaustiveSearchOneSequence,ExhaustiveSearchOneSequence,O_Search) // {
public:
	void	archive(RPNode node);
	void	initialize();
	void	oldLispInitialize(RPKeyedArguments kargs, RPLisp);
private:
		//! If we split the search over multiple processes set the num processes here
	uint	_NumberOfPartitions;
		//! Set the partition number here, 0 is first
	int	_PartitionNumber;
		//! If this is zero then generate ALL conformations
	int	_NumberOfConformationsPerSequence;
		//! If !UseRandomConformations then go through them systematically
	bool	_UseRandomConformations;
	RPScorerStatistics _Statistics;
	LongLongInt	_ConformationsBuilt;
public:
public:
	void setDefaultOptions();
	void setKeyedOptions(RPKeyedArguments options);
	void setOptions(RPCons options);

	virtual void run();

	O_ExhaustiveSearchOneSequence( const O_ExhaustiveSearchOneSequence& ss ); //!< Copy constructor


__END_CLASS_DEFINITION(O_ExhaustiveSearchOneSequence) //}




};
#endif //]
